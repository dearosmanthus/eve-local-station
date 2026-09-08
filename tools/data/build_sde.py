#!/usr/bin/env python3
"""Convert an explicitly supplied CCP JSONL SDE into offline application assets.

No network access. Base conversion uses the standard library; optional verified
engine state metadata uses the engine builder's pinned Protobuf dependency.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import re
import sys
import zipfile

PIPELINE_VERSION = 6
REQUIRED = ("_sde", "categories", "groups", "types", "dogmaAttributes",
            "dogmaEffects", "typeDogma", "marketGroups", "mapRegions", "mapConstellations",
            "mapSolarSystems", "mapStars", "mapStargates")
SLOT_EFFECTS = {"hiPower": "high", "medPower": "medium", "loPower": "low",
                "rigSlot": "rig", "subSystem": "subsystem"}
SHIP_ATTRIBUTES = {"hiSlots": "high_slots", "medSlots": "medium_slots",
                   "lowSlots": "low_slots", "rigSlots": "rig_slots",
                   "maxSubSystems": "subsystem_slots"}
SHIP_RESOURCES = {
    "cpuOutput": "base_cpu_output", "powerOutput": "base_powergrid_output",
    "droneCapacity": "drone_capacity", "droneBandwidth": "drone_bandwidth",
    "turretSlotsLeft": "turret_hardpoints", "launcherSlotsLeft": "launcher_hardpoints",
    "upgradeCapacity": "upgrade_capacity",
}
SLOT_MODIFIERS = {"hiSlotModifier": "high", "medSlotModifier": "medium", "lowSlotModifier": "low"}
HARDPOINT_MODIFIERS = {"turretHardPointModifier": "turret", "launcherHardPointModifier": "launcher"}
ATTRIBUTE_GROUPS = {"charge_group_ids": r"chargeGroup\d+",
                    "fit_ship_group_ids": r"canFitShipGroup\d+",
                    "fit_ship_type_ids": r"canFitShipType\d+"}
ENGINE_REVISION = "5772f9d6238a019b71f0fb235fbeeaf1338694f5"
ENGINE_FILES = ("types.pb2", "dogmaAttributes.pb2", "dogmaEffects.pb2", "typeDogma.pb2", "dbuffcollections.pb2")
MODULE_STATES = ("offline", "online", "active", "overloaded")


def canonical_json(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True,
                       separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class SdeSource:
    """Reads only named members, without extracting any ZIP paths to disk."""

    def __init__(self, path: Path):
        self.path = path
        self.archive = zipfile.ZipFile(path) if path.is_file() else None
        if self.archive:
            self.names = {}
            for name in self.archive.namelist():
                leaf = Path(name).name
                if leaf in self.names:
                    raise ValueError(f"Duplicate SDE member basename: {leaf}")
                self.names[leaf] = name

    def close(self):
        if self.archive:
            self.archive.close()

    def open(self, table: str):
        name = table + ".jsonl"
        if self.archive:
            if name not in self.names:
                raise ValueError(f"Missing required SDE member: {name}")
            return self.archive.open(self.names[name])
        target = self.path / name
        if not target.is_file():
            raise ValueError(f"Missing required SDE member: {name}")
        return target.open("rb")

    def records(self, table: str):
        seen = set()
        with self.open(table) as binary, io.TextIOWrapper(binary, encoding="utf-8-sig") as stream:
            for number, line in enumerate(stream, 1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                    key = record["_key"]
                    if key in seen:
                        raise ValueError(f"Duplicate _key {key}")
                    seen.add(key)
                except (ValueError, KeyError, TypeError) as exc:
                    raise ValueError(f"{table}.jsonl line {number}: {exc}") from exc
                yield record
        if not seen:
            raise ValueError(f"Required SDE member is empty: {table}.jsonl")

    def table(self, name: str):
        return {r["_key"]: r for r in self.records(name)}

    def source_digest(self):
        if self.archive:
            return sha256_file(self.path), "archive-sha256"
        # Directory hashes explicitly cover the required input files, in name order.
        digest = hashlib.sha256()
        for table in sorted(REQUIRED):
            digest.update((table + ".jsonl\0").encode())
            with self.open(table) as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            digest.update(b"\0")
        return digest.hexdigest(), "required-members-sha256"


def localized(value, language="en"):
    if isinstance(value, str):
        return value
    if not isinstance(value, dict) or language not in value:
        raise ValueError(f"Missing {language} localized name")
    return value[language]


def add_chinese_name(output, localized_names, key="name_zh"):
    """Retain only an official nonblank Chinese name; never translate locally."""
    value = localized_names.get("zh") if isinstance(localized_names, dict) else None
    if isinstance(value, str) and value.strip():
        output[key] = value.strip()


def localization_coverage(rows, canonical_key="name", translated_key="name_zh"):
    translated = [row for row in rows if row.get(translated_key)]
    return {"total": len(rows), "translated": len(translated),
            "differentFromEnglish": sum(row[translated_key] != row[canonical_key] for row in translated)}


def prune_market_groups(groups, used_ids):
    """Keep official categories used by fitting types and every ancestor."""
    retained = set()
    for leaf_id in sorted(used_ids):
        current = leaf_id
        path = set()
        while current is not None:
            if type(current) is not int or current <= 0:
                raise ValueError(f"Invalid market group ID: {current!r}")
            if current in path:
                raise ValueError(f"Cycle in market group ancestry at {current}")
            if current in retained:
                break  # This ancestor's whole path was already validated.
            row = groups.get(current)
            if row is None:
                raise ValueError(f"Missing referenced market group {current}")
            path.add(current)
            current = row.get("parentGroupID")
        retained.update(path)
    result = []
    for group_id in sorted(retained):
        row = groups[group_id]
        item = {"id": group_id, "parent_id": row.get("parentGroupID"), "name": localized(row["name"])}
        add_chinese_name(item, row["name"])
        result.append(item)
    return result


def finite_number(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"Invalid finite numeric field {label}: {value!r}")
    return value


def add_system_details(system, row, constellations, stars):
    """Join explicit static detail fields without inventing class semantics."""
    constellation_id = row["constellationID"]
    if type(constellation_id) is not int or constellation_id <= 0:
        raise ValueError(f"Invalid constellationID for system {row['_key']}")
    constellation = constellations.get(constellation_id)
    if constellation is None:
        raise ValueError(f"Unknown constellation {constellation_id}")
    if constellation["regionID"] != row["regionID"]:
        raise ValueError(f"Constellation/region mismatch for system {row['_key']}")
    system.update(constellation_id=constellation_id,
                  constellation_name=localized(constellation["name"]))
    add_chinese_name(system, constellation["name"], "constellation_name_zh")

    def optional_id(source, key, output_key):
        value = source.get(key)
        if value is not None:
            if type(value) is not int or value <= 0:
                raise ValueError(f"Invalid {key} for system {row['_key']}")
            system[output_key] = value

    def optional_text(source, key, output_key):
        value = source.get(key)
        if value is not None:
            if not isinstance(value, str):
                raise ValueError(f"Invalid {key} for system {row['_key']}")
            if value.strip():
                system[output_key] = value.strip()

    optional_text(row, "securityClass", "security_class")
    # These IDs classify several kinds of space, including normal high/lowsec.
    # Retain system and constellation source values separately, with no guessed
    # inheritance, C1-C6 conversion, or wormhole-only interpretation.
    optional_id(row, "wormholeClassID", "wormhole_class_id")
    optional_id(constellation, "wormholeClassID", "constellation_wormhole_class_id")
    if "planetIDs" in row:
        planets = row["planetIDs"]
        if (not isinstance(planets, list) or any(type(key) is not int or key <= 0 for key in planets)
                or len(set(planets)) != len(planets)):
            raise ValueError(f"Invalid planetIDs for system {row['_key']}")
        system["planet_count"] = len(planets)
    optional_id(row, "starID", "star_id")
    if "star_id" in system:
        star = stars.get(system["star_id"])
        if star is None or star["solarSystemID"] != row["_key"]:
            raise ValueError(f"Missing or mismatched star for system {row['_key']}")
        statistics = star.get("statistics", {})
        if not isinstance(statistics, dict):
            raise ValueError(f"Invalid star statistics for system {row['_key']}")
        optional_text(statistics, "spectralClass", "star_spectral_class")


def add_compatibility(item, row, values, attributes, attribute_groups, effect_names, bucket):
    """Expose only explicit SDE constraints, never infer fit limits from names.

All fields are additive to schema 1. A missing field means that this static
catalogue does not establish the constraint. A list with no entries means the
SDE has no positive entries for that allowlist, not a ban on every ship/charge.
"""
    item["attributes"] = {str(key): finite_number(value, f"{row['_key']}/attribute/{key}")
                          for key, value in values.items()}
    for source_name in ("capacity", "mass"):
        if source_name in row:
            item[source_name] = finite_number(row[source_name], source_name)

    def optional(source_name, target_name, *, integer=False, positive=False):
        key = attributes.get(source_name)
        if key not in values:
            return
        value = finite_number(values[key], source_name)
        if integer:
            if int(value) != value:
                raise ValueError(f"Non-integral compatibility value {source_name} on {row['_key']}")
            value = int(value)
        if not positive or value > 0:
            item[target_name] = value

    def positive_ids(group_name):
        result = set()
        for name, key in attribute_groups[group_name]:
            if key in values:
                value = finite_number(values[key], name)
                if int(value) != value:
                    raise ValueError(f"Non-integral group/type constraint {name} on {row['_key']}")
                if value > 0:
                    result.add(int(value))
        return sorted(result)

    optional("rigSize", "rig_size", integer=True, positive=True)
    optional("chargeSize", "charge_size", integer=True, positive=True)
    if bucket == "ships":
        for name, output_name in SHIP_RESOURCES.items():
            optional(name, output_name)
    elif bucket == "drones":
        optional("droneBandwidthUsed", "bandwidth_used")
    elif bucket == "modules":
        for group_name in ATTRIBUTE_GROUPS:
            item[group_name] = positive_ids(group_name)
        optional("fitsToShipType", "required_ship_type_id", integer=True, positive=True)
        optional("maxGroupFitted", "max_group_fitted", integer=True, positive=True)
        optional("upgradeCost", "upgrade_cost")
        item["requires_turret_hardpoint"] = "turretFitted" in effect_names
        item["requires_launcher_hardpoint"] = "launcherFitted" in effect_names
        if item["slot_type"] == "subsystem":
            optional("subSystemSlot", "subsystem_family", integer=True, positive=True)
            # The explicit effects distinguish operational modifiers from a
            # similarly named attribute which might serve another purpose.
            for effect, output, mapping in (("slotModifier", "slot_modifiers", SLOT_MODIFIERS),
                                             ("hardPointModifierEffect", "hardpoint_modifiers", HARDPOINT_MODIFIERS)):
                if effect in effect_names:
                    modifiers = {}
                    for name, slot_name in mapping.items():
                        key = attributes.get(name)
                        if key in values:
                            value = finite_number(values[key], name)
                            if int(value) != value:
                                raise ValueError(f"Non-integral {name} on subsystem {row['_key']}")
                            modifiers[slot_name] = int(value)
                    item[output] = modifiers


def verify_engine_pack(root: Path, sde_build: int):
    """Verify package identity and bytes; gameplay semantics need native tests."""
    path = root / "engine-manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if (manifest.get("schema_version") != 1 or manifest.get("server") != "tranquility"
            or manifest.get("upstream_revision") != ENGINE_REVISION
            or str(manifest.get("sde_build")) != str(sde_build)
            or not manifest.get("fsd_build")):
        raise ValueError("Engine pack schema/server/revision/data version does not match the catalogue")
    expected = manifest.get("files", {})
    for name in ENGINE_FILES:
        file = root / name
        if not file.is_file() or not file.stat().st_size or sha256_file(file) != expected.get(name):
            raise ValueError(f"Engine pack missing, empty or checksum mismatch: {name}")
    return {"manifestSha256": sha256_file(path), "upstreamRevision": ENGINE_REVISION,
            "sdeBuild": str(manifest["sde_build"]), "fsdBuild": manifest["fsd_build"],
            "files": {name: expected[name] for name in ENGINE_FILES}}


def module_state_metadata(effect_categories, has_capacitor_need):
    """Match pinned Item::new_module + collect_effects, not raw enum IDs.

The native enum orders Passive < Online < Active < Overload < Target < Area.
Consequently target/area effects do not themselves raise max_state. Presence of
capacitorNeed (including zero) raises it to Active, exactly as pass_2.rs does.
"""
    categories = set(effect_categories)
    if not categories <= set(range(8)):
        raise ValueError(f"Unknown engine effect categories: {sorted(categories)}")
    maximum = max(( {0: 0, 4: 1, 1: 2, 5: 3}.get(category, 0)
                    for category in categories), default=0)
    if has_capacitor_need:
        maximum = max(maximum, 2)
    return {"supported_states": list(MODULE_STATES[:maximum + 1]),
            "max_state": MODULE_STATES[maximum],
            "default_state": MODULE_STATES[min(maximum, 2)],
            "has_activation_effect": bool(categories & {1, 2, 3}),
            "has_overload_effect": 5 in categories}


def load_engine_module_states(root: Path):
    """Read already verified bytes including all upstream patches.

Raw SDE effect 16 is Active, but onlineEffect.yaml makes it Online; other
patches add Online calibration and Active weapon effects. Reading the actual
runtime package avoids reproducing those rules inaccurately in the catalogue.
"""
    import importlib.util
    vendor = Path(__file__).resolve().parents[2] / "native/vendor/eve-fit-os"
    spec = importlib.util.spec_from_file_location("_els_engine_pb2", vendor / "efos_pb2.py")
    pb = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(pb)
    except ImportError as exc:
        raise ValueError("Engine state metadata requires the pinned Protobuf build dependency; "
                         "install tools/engine_data/requirements.txt in the developer environment") from exc
    effects = pb.DogmaEffects.FromString((root / "dogmaEffects.pb2").read_bytes()).entries
    type_dogma = pb.TypeDogma.FromString((root / "typeDogma.pb2").read_bytes()).entries
    result = {}
    for type_id, row in type_dogma.items():
        categories = []
        for effect in row.dogmaEffects:
            if effect.effectID not in effects:
                raise ValueError(f"Engine type {type_id} references missing effect {effect.effectID}")
            categories.append(effects[effect.effectID].effectCategory)
        result[type_id] = module_state_metadata(categories, any(a.attributeID == 6 for a in row.dogmaAttributes))
    return result


def convert(source_path: Path, output: Path, expected_sha256: str | None = None,
            engine_pack: Path | None = None):
    source = SdeSource(source_path)
    try:
        digest, digest_kind = source.source_digest()
        if expected_sha256 and digest != expected_sha256.lower():
            raise ValueError("Source SHA256 does not match --expected-sha256")
        meta = source.table("_sde").get("sde")
        if not meta or type(meta.get("buildNumber")) is not int or meta["buildNumber"] <= 0:
            raise ValueError("_sde.jsonl must declare the sde buildNumber")
        synthetic = bool(meta.get("synthetic", False))
        provenance = {"source": "Synthetic test fixture" if synthetic else "CCP Tranquility SDE",
                      "buildNumber": meta["buildNumber"], "releaseDate": meta.get("releaseDate"),
                      "sourceSha256": digest, "sourceHashKind": digest_kind,
                      "synthetic": synthetic, "pipelineVersion": PIPELINE_VERSION}
        engine_info = verify_engine_pack(engine_pack, meta["buildNumber"]) if engine_pack else None
        engine_states = load_engine_module_states(engine_pack) if engine_pack else None
        categories, groups = source.table("categories"), source.table("groups")
        market_groups = source.table("marketGroups")
        attributes = {row["name"]: key for key, row in source.table("dogmaAttributes").items()}
        attribute_groups = {group_name: [(name, key) for name, key in attributes.items() if re.fullmatch(pattern, name)]
                            for group_name, pattern in ATTRIBUTE_GROUPS.items()}
        effects = {key: row["name"] for key, row in source.table("dogmaEffects").items()}
        missing_attributes = (set(SHIP_ATTRIBUTES) | {"cpu", "power"}) - attributes.keys()
        missing_effects = SLOT_EFFECTS.keys() - set(effects.values())
        if missing_attributes or missing_effects:
            raise ValueError(f"Incomplete Dogma definitions: attributes={sorted(missing_attributes)}, effects={sorted(missing_effects)}")
        dogma = source.table("typeDogma")
        catalogue = {"schemaVersion": 1, "provenance": provenance, "ships": [],
                     "modules": [], "drones": [], "charges": []}
        for row in source.records("types"):
            if not row.get("published", False):
                continue
            group = groups.get(row["groupID"])
            if group is None:
                raise ValueError(f"Unknown group {row['groupID']} for type {row['_key']}")
            category_id = group["categoryID"]
            category = categories.get(category_id)
            if category is None:
                raise ValueError(f"Unknown category {category_id}")
            bucket = {6: "ships", 7: "modules", 32: "modules", 18: "drones", 8: "charges"}.get(category_id)
            if bucket is None:
                continue
            item = {"type_id": row["_key"], "name": localized(row["name"]),
                    "group_id": row["groupID"], "group_name": localized(group["name"]),
                    "category_id": category_id, "category_name": localized(category["name"])}
            add_chinese_name(item, row["name"])
            add_chinese_name(item, group["name"], "group_name_zh")
            add_chinese_name(item, category["name"], "category_name_zh")
            if row.get("marketGroupID") is not None:
                market_group = row["marketGroupID"]
                if type(market_group) is not int or market_group <= 0:
                    raise ValueError(f"Invalid marketGroupID for type {row['_key']}")
                item["market_group_id"] = market_group
            if row["_key"] not in dogma:
                raise ValueError(f"Missing Dogma for published fitting type {row['_key']}")
            type_dogma = dogma[row["_key"]]
            values = {v["attributeID"]: v["value"] for v in type_dogma.get("dogmaAttributes", [])}
            item["effects"] = sorted({v["effectID"] for v in type_dogma.get("dogmaEffects", [])})
            effect_names = {effects[key] for key in item["effects"] if key in effects}
            if bucket == "ships":
                for source_name, target_name in SHIP_ATTRIBUTES.items():
                    value = finite_number(values.get(attributes.get(source_name), 0), source_name)
                    if value < 0 or int(value) != value:
                        raise ValueError(f"Invalid slot count for {row['_key']}: {source_name}")
                    item[target_name] = int(value)
                # These are raw hull capacities; installed subsystem slot modifiers
                # and family constraints belong to the calculation engine.
            elif bucket == "modules":
                slots = {SLOT_EFFECTS[effects[v["effectID"]]]
                         for v in type_dogma.get("dogmaEffects", [])
                         if effects.get(v["effectID"]) in SLOT_EFFECTS}
                if len(slots) > 1:
                    raise ValueError(f"Ambiguous slot effects for type {row['_key']}: {slots}")
                item["slot_type"] = next(iter(slots), None)
                # Static requirements only; hull/skill bonuses are engine calculations.
                item["base_cpu"] = values.get(attributes.get("cpu"), 0)
                item["base_powergrid"] = values.get(attributes.get("power"), 0)
                if engine_states is not None:
                    if row["_key"] not in engine_states:
                        raise ValueError(f"Missing patched engine state metadata for module {row['_key']}")
                    item.update(engine_states[row["_key"]])
            add_compatibility(item, row, values, attributes, attribute_groups, effect_names, bucket)
            if "volume" in row:
                item["volume"] = finite_number(row["volume"], "volume")
            catalogue[bucket].append(item)
        # maxSubSystems is a legacy maximum of 5 on current strategic cruisers.
        # The actual selectable families come from published hull-specific subsystems.
        families_by_ship = {}
        for module in catalogue["modules"]:
            if module.get("slot_type") == "subsystem" and module.get("required_ship_type_id") and module.get("subsystem_family"):
                families_by_ship.setdefault(module["required_ship_type_id"], set()).add(module["subsystem_family"])
        for ship in catalogue["ships"]:
            if ship["type_id"] in families_by_ship:
                ship["subsystem_families"] = sorted(families_by_ship[ship["type_id"]])
        for bucket in ("ships", "modules", "drones", "charges"):
            catalogue[bucket].sort(key=lambda item: (item["name"].casefold(), item["type_id"]))
        fitting_types = [item for bucket in ("ships", "modules", "drones", "charges") for item in catalogue[bucket]]
        catalogue["market_groups"] = prune_market_groups(
            market_groups, {item["market_group_id"] for item in fitting_types if "market_group_id" in item})
        regions = source.table("mapRegions")
        constellations, stars = source.table("mapConstellations"), source.table("mapStars")
        systems = []
        for row in source.records("mapSolarSystems"):
            region = regions.get(row["regionID"])
            if region is None:
                raise ValueError(f"Unknown region {row['regionID']}")
            system = {"id": row["_key"], "name": localized(row["name"]),
                      "region_id": row["regionID"], "region_name": localized(region["name"]),
                      "security": finite_number(row["securityStatus"], "securityStatus")}
            add_chinese_name(system, row["name"])
            add_chinese_name(system, region["name"], "region_name_zh")
            add_system_details(system, row, constellations, stars)
            for axis in "xyz":
                system[axis] = finite_number(row["position"][axis], "position." + axis)
            systems.append(system)
        systems.sort(key=lambda item: item["id"])
        system_ids = {system["id"] for system in systems}
        gates = set()
        for row in source.records("mapStargates"):
            a, b = row["solarSystemID"], row["destination"]["solarSystemID"]
            if a not in system_ids or b not in system_ids:
                raise ValueError(f"Stargate {row['_key']} references missing system")
            if a == b:
                raise ValueError(f"Self-loop stargate {row['_key']}")
            gates.add(tuple(sorted((a, b))))
        universe = {"schemaVersion": 1, "provenance": provenance, "systems": systems,
                    "gates": [{"from": a, "to": b} for a, b in sorted(gates)]}
        if not catalogue["ships"] or not systems:
            raise ValueError("Conversion produced no ships or systems; refusing empty data pack")
        files = {"catalogue.json": canonical_json(catalogue), "universe.json": canonical_json(universe)}
        manifest = {"schemaVersion": 1, "provenance": provenance,
                    "counts": {key: len(catalogue[key]) for key in ("ships", "modules", "drones", "charges")},
                    "files": {name: {"sha256": hashlib.sha256(content).hexdigest(), "bytes": len(content)}
                              for name, content in files.items()},
                    "engineDataIncluded": False,
                    "notice": "CCP data is not MIT licensed. See licenses/CCP-NOTICE.md."}
        manifest["counts"].update(systems=len(systems), gates=len(gates))
        manifest["counts"].update(marketGroups=len(catalogue["market_groups"]),
                                  typesWithoutMarketGroup=sum("market_group_id" not in item for item in fitting_types))
        used_groups = {item["group_id"]: item for bucket in ("ships", "modules", "drones", "charges")
                       for item in catalogue[bucket]}
        used_regions = {system["region_id"]: system for system in systems}
        used_constellations = {system["constellation_id"]: system for system in systems}
        manifest["localization"] = {
            "language": "zh", "fallbackLanguage": "en", "source": "official SDE name.zh",
            "itemNames": {key: localization_coverage(catalogue[key])
                          for key in ("ships", "modules", "drones", "charges")},
            "groupNames": localization_coverage(list(used_groups.values()), "group_name", "group_name_zh"),
            "systemNames": localization_coverage(systems),
            "regionNames": localization_coverage(list(used_regions.values()), "region_name", "region_name_zh"),
            "marketGroupNames": localization_coverage(catalogue["market_groups"]),
            "constellationNames": localization_coverage(list(used_constellations.values()),
                                                         "constellation_name", "constellation_name_zh"),
        }
        manifest["systemDetails"] = {
            "constellations": len(used_constellations),
            "fieldCoverage": {key: sum(key in system for system in systems) for key in (
                "constellation_id", "constellation_name_zh", "security_class", "wormhole_class_id",
                "constellation_wormhole_class_id", "planet_count", "star_id", "star_spectral_class")},
        }
        if engine_pack is not None:
            manifest["enginePack"] = engine_info
            manifest["engineDataIncluded"] = True
        # All validation has completed before mutating output. Atomically replace each file.
        output.mkdir(parents=True, exist_ok=True)
        files["manifest.json"] = canonical_json(manifest)
        for name, content in files.items():
            temp = output / (name + ".tmp")
            temp.write_bytes(content)
            temp.replace(output / name)
        return manifest
    finally:
        source.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Local official JSONL ZIP or directory")
    parser.add_argument("--output", required=True, type=Path, help="Generated app asset directory")
    parser.add_argument("--expected-sha256", help="Fail if the input hash differs")
    parser.add_argument("--engine-pack", type=Path, help="Explicit matching pack to checksum and declare included")
    args = parser.parse_args(argv)
    try:
        manifest = convert(args.input, args.output, args.expected_sha256, args.engine_pack)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as exc:
        parser.exit(1, f"SDE conversion failed: {exc}\n")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
