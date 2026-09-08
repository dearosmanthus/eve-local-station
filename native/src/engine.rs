use super::{DroneState, Failure, Fit, Result, SkillMode, SlotType, State, UPSTREAM_REVISION};
use eve_fit_os::calculate::item::{Item, ItemID};
use eve_fit_os::calculate::{self, DamageProfile};
use eve_fit_os::constant::patches::attr::*;
use eve_fit_os::fit::{
    FitContainer, ItemCharge, ItemDrone, ItemFit, ItemImplant, ItemModule, ItemSlot, ItemSlotType,
    ItemState,
};
use eve_fit_os::protobuf::Database;
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap};

fn state(state: State) -> ItemState {
    match state {
        State::Offline => ItemState::Passive,
        State::Online => ItemState::Online,
        State::Active => ItemState::Active,
        State::Overloaded => ItemState::Overload,
    }
}
fn slot(slot: SlotType) -> ItemSlotType {
    match slot {
        SlotType::High => ItemSlotType::High,
        SlotType::Medium => ItemSlotType::Medium,
        SlotType::Low => ItemSlotType::Low,
        SlotType::Rig => ItemSlotType::Rig,
        SlotType::Subsystem => ItemSlotType::SubSystem,
    }
}
fn drone_state(state: DroneState) -> ItemState {
    // Upstream's fallback_active promotes Online to Active. A drone in the bay
    // must be Passive to avoid contributing DPS and active bandwidth.
    match state {
        DroneState::Online => ItemState::Passive,
        DroneState::Active => ItemState::Active,
    }
}
fn attributes(item: &Item) -> BTreeMap<i32, f64> {
    item.attributes
        .iter()
        .filter_map(|(&id, attr)| attr.value.filter(|v| v.is_finite()).map(|v| (id, v)))
        .collect()
}

fn ship_stats(hull: &BTreeMap<i32, f64>) -> BTreeMap<&'static str, f64> {
    let mut stats = BTreeMap::new();
    for (name, id) in [
        ("cpu_output", 48),
        ("powergrid_output", 11),
        ("speed", 37),
        ("ehp", ATTR_EHP),
        ("align_time", ATTR_ALIGN_TIME),
        ("shield_hp", 263),
        ("armor_hp", 265),
        ("hull_hp", 9),
        ("capacitor_capacity", 482),
        ("capacitor_peak_recharge", ATTR_CAPACITOR_PEAK_RECHARGE),
        ("capacitor_peak_delta", ATTR_CAPACITOR_PEAK_DELTA),
        ("target_range", 76),
        ("scan_resolution", 564),
        ("max_targets", 192),
        ("signature_radius", 552),
        ("warp_speed", ATTR_WARP_SPEED),
        ("cargo_capacity", 38),
        ("drone_bay_capacity", 283),
        ("drone_bandwidth", 1271),
    ] {
        if let Some(value) = hull.get(&id) {
            stats.insert(name, *value);
        }
    }
    // These are additive totals. With no contributing item the actual total is
    // zero, even when Dogma has not materialized an attribute on the hull.
    for (name, id) in [
        ("cpu_used", 49),
        ("powergrid_used", 15),
        ("dps", ATTR_DAMAGE_PER_SECOND_WITHOUT_RELOAD),
        ("dps_with_reload", ATTR_DAMAGE_PER_SECOND_WITH_RELOAD),
        ("drone_dps", ATTR_DRONE_DAMAGE_PER_SECOND),
        ("alpha", ATTR_DAMAGE_ALPHA),
        ("capacitor_peak_drain", ATTR_CAPACITOR_PEAK_LOAD),
        ("drone_bay_used", ATTR_DRONE_CAPACITY_LOAD),
        ("drone_bandwidth_used", 1273),
        ("active_drones", ATTR_DRONE_ACTIVE),
    ] {
        stats.insert(name, hull.get(&id).copied().unwrap_or(0.0));
    }
    for (name, id) in [
        ("capacitor_recharge_time", 55),
        ("shield_recharge_time", 479),
    ] {
        if let Some(value) = hull.get(&id) {
            stats.insert(name, value / 1000.0);
        }
    }
    for (name, id) in [
        ("shield_resist_em", 271),
        ("shield_resist_explosive", 272),
        ("shield_resist_kinetic", 273),
        ("shield_resist_thermal", 274),
        ("armor_resist_em", 267),
        ("armor_resist_explosive", 268),
        ("armor_resist_kinetic", 269),
        ("armor_resist_thermal", 270),
        ("hull_resist_em", 113),
        ("hull_resist_explosive", 111),
        ("hull_resist_kinetic", 109),
        ("hull_resist_thermal", 110),
    ] {
        if let Some(resonance) = hull.get(&id) {
            stats.insert(name, 1.0 - resonance);
        }
    }
    if let Some(duration) = hull.get(&ATTR_CAPACITOR_DEPLETES_IN) {
        if *duration < 0.0 {
            stats.insert("capacitor_stable", 1.0);
        } else if *duration < 86400.0 {
            stats.insert("capacitor_stable", 0.0);
            stats.insert("capacitor_duration", *duration);
        } else {
            // Upstream stops the simulation after 24h; this is a bound, not a
            // prediction that the capacitor actually depleted at that time.
            stats.insert("capacitor_simulation_limit", 1.0);
        }
    }
    stats
}

fn item_stats(item: &Item) -> BTreeMap<&'static str, f64> {
    let attrs = attributes(item);
    let mut stats = BTreeMap::new();
    for (name, id) in [
        ("optimal_range", 54),
        ("falloff", 158),
        ("tracking_score", 160),
        ("dps", ATTR_DAMAGE_PER_SECOND_WITHOUT_RELOAD),
        ("volley", ATTR_DAMAGE_VOLLEY),
    ] {
        if let Some(value) = attrs.get(&id) {
            stats.insert(name, *value);
        }
    }
    if let Some(value) = attrs.get(&ATTR_CYCLE_TIME) {
        stats.insert("cycle_time", value / 1000.0);
    }
    if let Some(charge) = &item.charge {
        let charge_attrs = attributes(charge);
        if let Some(value) = charge_attrs.get(&281) {
            stats.insert("charge_flight_time", value / 1000.0);
        }
        if let Some(value) = charge_attrs.get(&37) {
            stats.insert("charge_velocity", *value);
        }
    }
    stats
}

fn total_alpha(hull: &BTreeMap<i32, f64>, items: &[Item]) -> f64 {
    // The pinned upstream damageAlpha patch targets modules only. Its drone
    // damageVolley is nevertheless fully computed (skills/ship bonuses). Add
    // each active drone's volley once; drone quantities are already expanded.
    let drone_volley: f64 = items
        .iter()
        .filter(|item| {
            matches!(
                item.slot.slot_type,
                eve_fit_os::calculate::item::SlotType::DroneBay { .. }
            ) && item.state.is_active()
        })
        .filter_map(|item| {
            item.attributes
                .get(&ATTR_DAMAGE_VOLLEY)
                .and_then(|attribute| attribute.value)
                .filter(|value| value.is_finite())
        })
        .sum();
    hull.get(&ATTR_DAMAGE_ALPHA).copied().unwrap_or(0.0) + drone_volley
}
fn require_type(db: &Database, id: i32, categories: &[i32], label: &str) -> Result<()> {
    let typ = db.types.get(&id).ok_or_else(|| {
        Failure::new(
            "UNKNOWN_TYPE",
            format!("{label} type {id} is absent from local data"),
        )
    })?;
    if !categories.is_empty() && !categories.contains(&typ.category_id) {
        return Err(Failure::new(
            "INVALID_FIT",
            format!("Type {id} is not a valid {label}"),
        ));
    }
    if !db.type_dogma.contains_key(&id) {
        return Err(Failure::new(
            "DATA_INVALID",
            format!("Dogma data missing for {label} {id}"),
        ));
    }
    Ok(())
}

pub(super) fn calculate(data_path: &str, fit: &Fit) -> Result<Value> {
    let db = Database::init_from_root(data_path)
        .map_err(|e| Failure::new("DATA_INVALID", format!("Cannot load engine protobuf: {e}")))?;
    require_type(&db, fit.ship_type_id, &[6], "ship")?;
    require_type(&db, 1373, &[], "character")?;
    for module in &fit.modules {
        let category = if module.slot_type == SlotType::Subsystem {
            &[32][..]
        } else {
            &[7][..]
        };
        require_type(&db, module.type_id, category, "module")?;
        if let Some(id) = module.charge_type_id {
            require_type(&db, id, &[8], "charge")?;
        }
    }
    for drone in &fit.drones {
        require_type(&db, drone.type_id, &[18], "drone")?;
    }
    for implant in &fit.implants {
        require_type(&db, implant.type_id, &[20], "implant")?;
    }
    let mut skills: HashMap<i32, u8> = match fit.skill_mode {
        SkillMode::Custom => HashMap::new(),
        SkillMode::All5 => db
            .types
            .iter()
            .filter(|(_, typ)| typ.category_id == 16)
            .map(|(&id, _)| (id, 5))
            .collect(),
    };
    for (key, &level) in &fit.skills {
        let id = key
            .parse::<i32>()
            .map_err(|_| Failure::new("INVALID_FIT", "Invalid skill ID"))?;
        require_type(&db, id, &[16], "skill")?;
        skills.insert(id, level);
    }
    let item_fit = ItemFit {
        ship_type_id: fit.ship_type_id,
        damage_profile: DamageProfile::default(),
        modules: fit
            .modules
            .iter()
            .map(|m| ItemModule {
                item_id: ItemID::Item(m.type_id),
                slot: ItemSlot {
                    slot_type: slot(m.slot_type),
                    index: m.index,
                },
                state: state(m.state),
                charge: m.charge_type_id.map(|type_id| ItemCharge { type_id }),
            })
            .collect(),
        drones: fit
            .drones
            .iter()
            .flat_map(|d| {
                (0..d.quantity).map(move |_| ItemDrone {
                    item_id: ItemID::Item(d.type_id),
                    group_id: 0,
                    state: drone_state(d.state),
                })
            })
            .collect(),
        implants: fit
            .implants
            .iter()
            .map(|i| ItemImplant {
                type_id: i.type_id,
                index: i.index,
            })
            .collect(),
        fighters: vec![],
        boosters: vec![],
    };
    let container = FitContainer::new(item_fit, skills, HashMap::new());
    let output = calculate::calculate(&container, &db);
    let hull = attributes(&output.hull);
    let mut stats = ship_stats(&hull);
    stats.insert("alpha", total_alpha(&hull, &output.modules));
    let diagnostics:Vec<_>=eve_fit_os::validate::validate_fit(&container,&output,&db).into_iter().map(|issue| {
        let severity=match issue.kind { eve_fit_os::validate::ValidationIssueKind::Error(_)=>"error",eve_fit_os::validate::ValidationIssueKind::Warning(_)=>"warning" };
        json!({"severity":severity,"slot_type":format!("{:?}",issue.slot_type),"index":issue.index,"message":format!("{:?}",issue.kind)})
    }).collect();
    let modules:Vec<_>=output.modules.iter().map(|item|json!({"type_id":item.item_id.as_type_id(&container),"slot_type":format!("{:?}",item.slot.slot_type),"index":item.slot.index,"effective_state":format!("{:?}",item.state),"attributes":attributes(item),"stats":item_stats(item),"charge_attributes":item.charge.as_ref().map(|charge|attributes(charge))})).collect();
    Ok(
        json!({"engine":"eve-fit-os","upstream_revision":UPSTREAM_REVISION,"pyfa_verified":false,"damage_profile":{"em":0.25,"thermal":0.25,"kinetic":0.25,"explosive":0.25},"stats":stats,"ship_attributes":hull,"module_attributes":modules,"diagnostics":diagnostics}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn in_bay_drone_stays_passive_after_upstream_normalization() {
        let category: eve_fit_os::calculate::item::EffectCategory =
            drone_state(DroneState::Online).into();
        assert_eq!(
            category.fallback_active(),
            eve_fit_os::calculate::item::EffectCategory::Passive
        );
        let active: eve_fit_os::calculate::item::EffectCategory =
            drone_state(DroneState::Active).into();
        assert!(active.fallback_active().is_active());
    }
    #[test]
    fn additive_empty_totals_are_zero_but_unknown_ship_stats_stay_absent() {
        let stats = ship_stats(&BTreeMap::new());
        for name in ["dps", "drone_dps", "alpha", "drone_bandwidth_used"] {
            assert_eq!(stats[name], 0.0);
        }
        assert!(!stats.contains_key("ehp"));
        assert!(!stats.contains_key("capacitor_stable"));
    }
    #[test]
    fn physical_units_resistances_and_capacitor_limit_are_explicit() {
        let stats = ship_stats(&BTreeMap::from([
            (55, 93750.0),
            (271, 0.8),
            (ATTR_CAPACITOR_DEPLETES_IN, 86401.0),
        ]));
        assert_eq!(stats["capacitor_recharge_time"], 93.75);
        assert!((stats["shield_resist_em"] - 0.2).abs() < 1e-12);
        assert_eq!(stats["capacitor_simulation_limit"], 1.0);
        assert!(!stats.contains_key("capacitor_duration"));
        assert!(!stats.contains_key("capacitor_stable"));
    }
    #[test]
    fn total_volley_includes_each_active_drone_but_not_bay_drones() {
        use eve_fit_os::calculate::item::{Attribute, EffectCategory};
        let mut drone = Item::new_drone(ItemID::Item(2456), 0, EffectCategory::Active);
        let mut volley = Attribute::new_base(20.0);
        volley.value = Some(20.0);
        drone.attributes.insert(ATTR_DAMAGE_VOLLEY, volley);
        let mut bay = drone.clone();
        bay.state = EffectCategory::Passive;
        assert_eq!(
            total_alpha(
                &BTreeMap::from([(ATTR_DAMAGE_ALPHA, 50.0)]),
                &[drone.clone(), drone, bay]
            ),
            90.0
        );
    }
}
