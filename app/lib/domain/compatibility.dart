import 'catalogue.dart';
import 'fit.dart';

class FitLayout {
  const FitLayout(this.slots, this.turretHardpoints, this.launcherHardpoints);
  final Map<Slot, int> slots;
  final int? turretHardpoints;
  final int? launcherHardpoints;
}

FitLayout fitLayout(Catalogue catalogue, Fit fit) {
  final ship = catalogue.byId[fit.shipTypeId];
  final slots = {for (final slot in Slot.values) slot: ship?.slots[slot] ?? 0};
  final families = ship?.integers('subsystem_families') ?? [];
  if (families.isNotEmpty) slots[Slot.subsystem] = families.length;
  var turret = ship?.integer('turret_hardpoints');
  var launcher = ship?.integer('launcher_hardpoints');
  final appliedFamilies = <int>{};
  for (final fitted in fit.modules.where(
    (module) => module.slot == Slot.subsystem,
  )) {
    final type = catalogue.byId[fitted.typeId];
    if (type == null || type.slot != Slot.subsystem) continue;
    final requiredShip = type.integer('required_ship_type_id');
    if (requiredShip != null && requiredShip != fit.shipTypeId) continue;
    final family = type.integer('subsystem_family');
    if (family != null && !appliedFamilies.add(family)) continue;
    final modifiers =
        type.data['slot_modifiers'] as Map<String, dynamic>? ?? {};
    for (final slot in [Slot.high, Slot.medium, Slot.low]) {
      slots[slot] =
          (slots[slot]! + ((modifiers[slot.key] as num?)?.toInt() ?? 0)).clamp(
        0,
        8,
      );
    }
    final hardpoints =
        type.data['hardpoint_modifiers'] as Map<String, dynamic>? ?? {};
    if (turret != null) turret += (hardpoints['turret'] as num?)?.toInt() ?? 0;
    if (launcher != null) {
      launcher += (hardpoints['launcher'] as num?)?.toInt() ?? 0;
    }
  }
  return FitLayout(slots, turret, launcher);
}

/// Static SDE filters reject only known incompatibilities. Missing metadata is
/// unknown, never an invented restriction. CPU/PG totals need skill/effect-aware
/// native calculation, so they are deliberately not guessed in this layer.
List<String> moduleCompatibility({
  required EveType module,
  required Catalogue catalogue,
  required Fit fit,
  required Slot slot,
  required int index,
}) {
  final issues = <String>[];
  final ship = catalogue.byId[fit.shipTypeId];
  final layout = fitLayout(catalogue, fit);
  if (module.slot != null && module.slot != slot) issues.add('槽位类型不符');
  if (index < 0 || index >= (layout.slots[slot] ?? 0)) issues.add('超出当前舰船槽位');
  if (ship == null) return issues;
  final groups = module.integers('fit_ship_group_ids');
  final types = module.integers('fit_ship_type_ids');
  if ((groups.isNotEmpty || types.isNotEmpty) &&
      !types.contains(ship.id) &&
      !groups.contains(ship.groupId) &&
      (groups.isEmpty || ship.groupId != null)) {
    issues.add('不适用于此舰船类型');
  }
  final requiredShip = module.integer('required_ship_type_id');
  if (requiredShip != null && requiredShip > 0 && requiredShip != ship.id) {
    issues.add('仅适用于另一种舰船');
  }
  final rigSize = module.integer('rig_size');
  final shipRigSize = ship.integer('rig_size');
  if (slot == Slot.rig &&
      rigSize != null &&
      shipRigSize != null &&
      rigSize > 0 &&
      shipRigSize > 0 &&
      rigSize != shipRigSize) {
    issues.add('改装件尺寸与舰船不符');
  }
  final other = fit.modules
      .where((fitted) => fitted.slot != slot || fitted.index != index)
      .map((fitted) => catalogue.byId[fitted.typeId])
      .whereType<EveType>()
      .toList();
  if (module.data['requires_turret_hardpoint'] == true &&
      layout.turretHardpoints != null &&
      other
              .where((type) => type.data['requires_turret_hardpoint'] == true)
              .length >=
          layout.turretHardpoints!) {
    issues.add('没有剩余炮台挂点');
  }
  if (module.data['requires_launcher_hardpoint'] == true &&
      layout.launcherHardpoints != null &&
      other
              .where((type) => type.data['requires_launcher_hardpoint'] == true)
              .length >=
          layout.launcherHardpoints!) {
    issues.add('没有剩余发射器挂点');
  }
  final maxGroup = module.integer('max_group_fitted');
  if (maxGroup != null &&
      maxGroup > 0 &&
      module.groupId != null &&
      other.where((type) => type.groupId == module.groupId).length >=
          maxGroup) {
    issues.add('已达到此模块组的装配上限');
  }
  if (slot == Slot.subsystem) {
    final family = module.integer('subsystem_family');
    final families = ship.integers('subsystem_families');
    if (family != null &&
        index < families.length &&
        families[index] != family) {
      issues.add('此位置需要另一类子系统');
    }
    if (family != null &&
        other.any(
          (type) =>
              type.slot == Slot.subsystem &&
              type.integer('subsystem_family') == family,
        )) {
      issues.add('同类子系统只能安装一个');
    }
  }
  return issues;
}

List<String> chargeCompatibility(EveType module, EveType charge) {
  final issues = <String>[];
  final groups = module.integers('charge_group_ids');
  if (module.data.containsKey('charge_group_ids')) {
    if (groups.isEmpty) {
      issues.add('此模块不装载弹药');
    } else if (charge.groupId != null && !groups.contains(charge.groupId)) {
      issues.add('弹药组别不兼容');
    }
  }
  final size = module.integer('charge_size');
  final chargeSize = charge.integer('charge_size');
  if (size != null &&
      chargeSize != null &&
      size > 0 &&
      chargeSize > 0 &&
      size != chargeSize) {
    issues.add('弹药尺寸不兼容');
  }
  final capacity = module.number('capacity');
  final volume = charge.number('volume');
  if (capacity != null &&
      volume != null &&
      capacity > 0 &&
      volume > capacity + 0.0000001) {
    issues.add('单发弹药体积超过模块容量');
  }
  return issues;
}

List<String> fittingCompatibilityIssues(Catalogue catalogue, Fit fit) {
  final issues = <String>[];
  for (final fitted in fit.modules) {
    final module = catalogue.byId[fitted.typeId];
    if (module == null) {
      issues.add('本地目录缺少模块 #${fitted.typeId}');
      continue;
    }
    if (!supportedModuleStates(module).contains(fitted.state)) {
      issues.add('${module.displayName}：不支持当前${fitted.state.label}状态，请选择可用状态');
    }
    for (final issue in moduleCompatibility(
      module: module,
      catalogue: catalogue,
      fit: fit,
      slot: fitted.slot,
      index: fitted.index,
    )) {
      issues.add('${module.displayName}：$issue');
    }
    if (fitted.chargeTypeId != null) {
      final charge = catalogue.byId[fitted.chargeTypeId];
      if (charge == null) {
        issues.add('${module.displayName}：本地目录缺少装载弹药');
      } else {
        for (final issue in chargeCompatibility(module, charge)) {
          issues.add('${module.displayName} / ${charge.displayName}：$issue');
        }
      }
    }
  }
  return issues;
}
