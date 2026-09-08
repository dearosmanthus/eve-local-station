"""Synthetic conversion fixtures plus explicit checks of shipped real SDE rows."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("build_sde", ROOT / "tools/data/build_sde.py")
build_sde = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_sde)


def fixture():
    return {
        "_sde": [{"_key": "sde", "buildNumber": 1, "releaseDate": "synthetic", "synthetic": True}],
        "categories": [{"_key": 6, "name": {"en": "Synthetic Ship"}}, {"_key": 7, "name": {"en": "Synthetic Module"}}],
        "groups": [{"_key": 1, "categoryID": 6, "name": {"en": "Synthetic Hulls"}},
                   {"_key": 2, "categoryID": 7, "name": {"en": "Synthetic Modules"}}],
        "types": [{"_key": 9000001, "groupID": 1, "name": {"en": "Synthetic Ship"}, "published": True},
                  {"_key": 9000002, "groupID": 2, "name": {"en": "Synthetic Module"}, "published": True},
                  {"_key": 9000003, "groupID": 1, "name": {"en": "Unpublished Fixture"}, "published": False}],
        "dogmaAttributes": [{"_key": key, "name": name} for key, name in
                            [(14, "hiSlots"), (13, "medSlots"), (12, "lowSlots"), (1137, "rigSlots"),
                             (1367, "maxSubSystems"), (50, "cpu"), (30, "power")]],
        "dogmaEffects": [{"_key": key, "name": name} for key, name in
                         [(12, "hiPower"), (13, "medPower"), (11, "loPower"), (2663, "rigSlot"), (3772, "subSystem")]],
        "typeDogma": [{"_key": 9000001, "dogmaAttributes": [{"attributeID": 14, "value": 2}]},
                      {"_key": 9000002, "dogmaEffects": [{"effectID": 12, "isDefault": False}]}],
        "marketGroups": [{"_key": 1, "name": {"en": "Synthetic Market Root"}}],
        "mapRegions": [{"_key": 1, "name": {"en": "Synthetic Region"}}],
        "mapConstellations": [{"_key": 2001, "regionID": 1,
                               "name": {"en": "Synthetic Constellation"}}],
        "mapSolarSystems": [{"_key": n, "name": {"en": f"Synthetic {n}"}, "regionID": 1,
                             "constellationID": 2001,
                             "securityStatus": 0.8, "position": {"x": n, "y": 0, "z": 0}} for n in (1, 2, 3)],
        "mapStars": [{"_key": 1001, "solarSystemID": 1,
                       "statistics": {"spectralClass": "SYNTHETIC"}}],
        "mapStargates": [{"_key": 1, "solarSystemID": 1, "destination": {"solarSystemID": 2}},
                         {"_key": 2, "solarSystemID": 2, "destination": {"solarSystemID": 1}}],
    }


def write_fixture(folder, records):
    folder.mkdir(parents=True, exist_ok=True)
    for name, rows in records.items():
        (folder / (name + ".jsonl")).write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")


def compatibility_fixture():
    """Invented values using genuine field names; no measured EVE statistics."""
    records = fixture()
    records["dogmaAttributes"] += [{"_key": key, "name": name} for key, name in (
        (48, "cpuOutput"), (11, "powerOutput"), (283, "droneCapacity"), (1271, "droneBandwidth"),
        (102, "turretSlotsLeft"), (101, "launcherSlotsLeft"), (1132, "upgradeCapacity"),
        (1547, "rigSize"), (128, "chargeSize"), (604, "chargeGroup1"), (605, "chargeGroup2"),
        (606, "chargeGroup3"), (1298, "canFitShipGroup01"), (1302, "canFitShipType1"),
        (1380, "fitsToShipType"), (1544, "maxGroupFitted"), (1272, "droneBandwidthUsed"),
        (1366, "subSystemSlot"), (1374, "hiSlotModifier"), (1375, "medSlotModifier"),
        (1376, "lowSlotModifier"), (1368, "turretHardPointModifier"), (1369, "launcherHardPointModifier"),
    )]
    records["dogmaEffects"] += [{"_key": key, "name": name} for key, name in (
        (40, "launcherFitted"), (42, "turretFitted"), (3774, "slotModifier"), (3773, "hardPointModifierEffect"),
    )]
    return records


def set_attributes(records, type_id, values):
    record = next(row for row in records["typeDogma"] if row["_key"] == type_id)
    record["dogmaAttributes"] = [{"attributeID": key, "value": value} for key, value in values.items()]


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        write_fixture(self.source, fixture())

    def tearDown(self):
        self.temp.cleanup()

    def catalogue_for(self, records):
        write_fixture(self.source, records)
        build_sde.convert(self.source, self.root / "out")
        return json.loads((self.root / "out/catalogue.json").read_text(encoding="utf-8"))

    def test_schema_slot_effects_and_undirected_deduplication(self):
        report = build_sde.convert(self.source, self.root / "out")
        catalogue = json.loads((self.root / "out/catalogue.json").read_text())
        universe = json.loads((self.root / "out/universe.json").read_text())
        self.assertEqual(report["counts"]["ships"], 1)
        self.assertEqual(catalogue["ships"][0]["high_slots"], 2)
        self.assertEqual(catalogue["modules"][0]["slot_type"], "high")
        self.assertEqual(universe["gates"], [{"from": 1, "to": 2}])
        self.assertEqual(len(universe["systems"]), 3)  # isolated systems are retained
        self.assertTrue(report["provenance"]["synthetic"])
        self.assertFalse(report["engineDataIncluded"])

    def test_repeat_build_is_byte_identical(self):
        for name in ("a", "b"):
            build_sde.convert(self.source, self.root / name)
        for name in ("catalogue.json", "universe.json", "manifest.json"):
            self.assertEqual((self.root / "a" / name).read_bytes(), (self.root / "b" / name).read_bytes())

    def test_zip_and_directory_data_match(self):
        archive_path = self.root / "source.zip"
        with zipfile.ZipFile(archive_path, "w") as archive:
            for path in self.source.iterdir():
                archive.write(path, "nested/" + path.name)
        a = build_sde.convert(self.source, self.root / "a")
        b = build_sde.convert(archive_path, self.root / "b")
        self.assertEqual(a["counts"], b["counts"])
        self.assertNotEqual(a["provenance"]["sourceHashKind"], b["provenance"]["sourceHashKind"])

    def test_hash_mismatch_fails_before_output(self):
        with self.assertRaisesRegex(ValueError, "SHA256"):
            build_sde.convert(self.source, self.root / "out", "0" * 64)
        self.assertFalse((self.root / "out").exists())

    def test_dangling_gate_fails(self):
        records = fixture()
        records["mapStargates"][0]["destination"]["solarSystemID"] = 99
        write_fixture(self.source, records)
        with self.assertRaisesRegex(ValueError, "missing system"):
            build_sde.convert(self.source, self.root / "out")

    def test_duplicate_key_fails(self):
        records = fixture()
        records["types"].append(records["types"][0])
        write_fixture(self.source, records)
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            build_sde.convert(self.source, self.root / "out")

    def test_nonfinite_coordinate_fails(self):
        records = fixture()
        records["mapSolarSystems"][0]["position"]["x"] = float("nan")
        write_fixture(self.source, records)
        with self.assertRaisesRegex(ValueError, "finite numeric"):
            build_sde.convert(self.source, self.root / "out")

    def test_missing_member_fails(self):
        (self.source / "mapStargates.jsonl").unlink()
        with self.assertRaisesRegex(ValueError, "Missing required"):
            build_sde.convert(self.source, self.root / "out")

    def test_empty_member_fails(self):
        (self.source / "typeDogma.jsonl").write_text("")
        with self.assertRaisesRegex(ValueError, "empty"):
            build_sde.convert(self.source, self.root / "out")

    def test_unknown_category_fails(self):
        records = fixture()
        records["groups"][0]["categoryID"] = 999
        write_fixture(self.source, records)
        with self.assertRaisesRegex(ValueError, "Unknown category"):
            build_sde.convert(self.source, self.root / "out")

    def test_partial_dogma_fails(self):
        records = fixture()
        records["typeDogma"].pop()
        write_fixture(self.source, records)
        with self.assertRaisesRegex(ValueError, "Missing Dogma"):
            build_sde.convert(self.source, self.root / "out")

    def test_ship_resources_and_raw_attributes_preserve_zero_and_provenance(self):
        records = compatibility_fixture()
        set_attributes(records, 9000001, {14: 2, 48: 100, 11: 40, 283: 0, 1271: 0,
                                         102: 2, 101: 0, 1132: 400, 1547: 1})
        ship = self.catalogue_for(records)["ships"][0]
        self.assertEqual(ship["base_cpu_output"], 100)
        self.assertEqual(ship["base_powergrid_output"], 40)
        self.assertEqual(ship["drone_capacity"], 0)
        self.assertEqual(ship["drone_bandwidth"], 0)
        self.assertEqual(ship["turret_hardpoints"], 2)
        self.assertEqual(ship["launcher_hardpoints"], 0)
        self.assertEqual(ship["rig_size"], 1)
        self.assertEqual(ship["attributes"]["48"], 100)

    def test_positive_allowlists_are_preserved_separately_without_intersection(self):
        records = compatibility_fixture()
        set_attributes(records, 9000002, {604: 88, 605: 83, 606: 0, 1298: 25, 1302: 9000001,
                                         1380: 9000001, 1544: 1})
        module = self.catalogue_for(records)["modules"][0]
        self.assertEqual(module["charge_group_ids"], [83, 88])
        self.assertEqual(module["fit_ship_group_ids"], [25])
        self.assertEqual(module["fit_ship_type_ids"], [9000001])
        self.assertEqual(module["required_ship_type_id"], 9000001)
        self.assertEqual(module["max_group_fitted"], 1)

    def test_missing_charge_size_remains_unknown_and_capacity_keeps_units(self):
        records = compatibility_fixture()
        records["types"][1]["capacity"] = 1.2
        records["types"][1]["volume"] = 10
        set_attributes(records, 9000002, {604: 385})
        module = self.catalogue_for(records)["modules"][0]
        self.assertNotIn("charge_size", module)
        self.assertEqual(module["capacity"], 1.2)
        self.assertEqual(module["volume"], 10)
        self.assertEqual(module["charge_group_ids"], [385])

    def test_hardpoint_requirements_come_from_effects(self):
        records = compatibility_fixture()
        records["typeDogma"][1]["dogmaEffects"].append({"effectID": 40, "isDefault": False})
        module = self.catalogue_for(records)["modules"][0]
        self.assertTrue(module["requires_launcher_hardpoint"])
        self.assertFalse(module["requires_turret_hardpoint"])
        self.assertEqual(module["effects"], [12, 40])

    def test_subsystem_families_and_signed_slot_impacts_are_derived(self):
        records = compatibility_fixture()
        records["categories"].append({"_key": 32, "name": {"en": "Synthetic Subsystem"}})
        records["groups"][1]["categoryID"] = 32
        records["typeDogma"][1]["dogmaEffects"] = [
            {"effectID": key, "isDefault": False} for key in (3772, 3773, 3774)]
        set_attributes(records, 9000002, {1366: 127, 1380: 9000001, 1374: 3, 1375: -1, 1376: 0,
                                         1368: 2, 1369: 1})
        catalogue = self.catalogue_for(records)
        self.assertEqual(catalogue["ships"][0]["subsystem_families"], [127])
        subsystem = catalogue["modules"][0]
        self.assertEqual(subsystem["subsystem_family"], 127)
        self.assertEqual(subsystem["slot_modifiers"], {"high": 3, "medium": -1, "low": 0})
        self.assertEqual(subsystem["hardpoint_modifiers"], {"turret": 2, "launcher": 1})

    def test_subsystem_modifier_attributes_without_effect_are_not_applied(self):
        records = compatibility_fixture()
        records["categories"].append({"_key": 32, "name": {"en": "Synthetic Subsystem"}})
        records["groups"][1]["categoryID"] = 32
        records["typeDogma"][1]["dogmaEffects"] = [{"effectID": 3772, "isDefault": False}]
        set_attributes(records, 9000002, {1366: 127, 1380: 9000001, 1374: 3})
        subsystem = self.catalogue_for(records)["modules"][0]
        self.assertNotIn("slot_modifiers", subsystem)
        self.assertNotIn("hardpoint_modifiers", subsystem)
        self.assertEqual(subsystem["attributes"]["1374"], 3)

    def test_nonfinite_unused_dogma_attribute_is_rejected(self):
        records = compatibility_fixture()
        set_attributes(records, 9000002, {99999: float("nan")})
        with self.assertRaisesRegex(ValueError, "finite numeric"):
            self.catalogue_for(records)

    def test_fractional_group_restriction_is_not_truncated(self):
        records = compatibility_fixture()
        set_attributes(records, 9000002, {604: 83.5})
        with self.assertRaisesRegex(ValueError, "Non-integral"):
            self.catalogue_for(records)

    def test_declared_but_missing_engine_pack_does_not_mark_data_included(self):
        with self.assertRaises(OSError):
            build_sde.convert(self.source, self.root / "out", engine_pack=self.root / "missing-pack")
        self.assertFalse((self.root / "out").exists())

    def test_engine_pack_build_mismatch_blocks_bundle_before_writing(self):
        pack = self.root / "engine"
        pack.mkdir()
        (pack / "engine-manifest.json").write_text(json.dumps({
            "schema_version": 1, "server": "tranquility", "upstream_revision": build_sde.ENGINE_REVISION,
            "sde_build": "wrong-build", "fsd_build": "synthetic", "files": {},
        }), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "does not match"):
            build_sde.convert(self.source, self.root / "out", engine_pack=pack)
        self.assertFalse((self.root / "out").exists())

    def test_module_state_enum_order_is_not_raw_effect_category_order(self):
        self.assertEqual(build_sde.module_state_metadata([0, 4], False)["supported_states"],
                         ["offline", "online"])
        self.assertEqual(build_sde.module_state_metadata([0, 1], False)["default_state"], "active")
        target_only = build_sde.module_state_metadata([0, 2, 3], False)
        self.assertEqual(target_only["max_state"], "offline")
        self.assertTrue(target_only["has_activation_effect"])

    def test_zero_capacitor_need_presence_promotes_active_but_never_overload(self):
        state = build_sde.module_state_metadata([0, 4], True)
        self.assertEqual(state["supported_states"], ["offline", "online", "active"])
        self.assertEqual(state["default_state"], "active")
        self.assertFalse(state["has_overload_effect"])

    def test_overload_is_available_but_not_the_default(self):
        state = build_sde.module_state_metadata([0, 4, 1, 5], True)
        self.assertEqual(state["max_state"], "overloaded")
        self.assertEqual(state["default_state"], "active")
        self.assertTrue(state["has_overload_effect"])

    def test_unknown_engine_effect_category_fails(self):
        with self.assertRaisesRegex(ValueError, "Unknown engine effect"):
            build_sde.module_state_metadata([8], False)

    def test_real_shipped_module_states_match_pinned_patched_engine(self):
        catalogue = json.loads((ROOT / "app/assets/data/catalogue.json").read_text(encoding="utf-8"))
        self.assertFalse(catalogue["provenance"]["synthetic"])
        modules = {row["type_id"]: row for row in catalogue["modules"]}
        for type_id, name, expected_default, expected_max in (
            (519, "Gyrostabilizer II", "online", "online"),
            (2889, "200mm AutoCannon II", "active", "overloaded"),
            (31788, "Small Core Defense Field Extender I", "online", "online"),
            (45601, "Tengu Offensive - Accelerated Ejection Bay", "offline", "offline"),
        ):
            with self.subTest(type_id=type_id):
                self.assertEqual(modules[type_id]["name"], name)
                self.assertEqual(modules[type_id]["default_state"], expected_default)
                self.assertEqual(modules[type_id]["max_state"], expected_max)
                self.assertIn(expected_default, modules[type_id]["supported_states"])

    def test_official_chinese_names_are_additive_and_coverage_is_explicit(self):
        records = fixture()
        records["types"][0]["name"]["zh"] = "合成测试舰船"
        records["groups"][0]["name"]["zh"] = "合成测试分类"
        records["mapRegions"][0]["name"]["zh"] = "合成测试星域"
        records["mapSolarSystems"][0]["name"]["zh"] = "合成测试星系"
        catalogue = self.catalogue_for(records)
        ship = catalogue["ships"][0]
        self.assertEqual(ship["name"], "Synthetic Ship")
        self.assertEqual(ship["name_zh"], "合成测试舰船")
        self.assertEqual(ship["group_name_zh"], "合成测试分类")
        universe = json.loads((self.root / "out/universe.json").read_text(encoding="utf-8"))
        self.assertEqual(universe["systems"][0]["name"], "Synthetic 1")
        self.assertEqual(universe["systems"][0]["name_zh"], "合成测试星系")
        self.assertEqual(universe["systems"][0]["region_name_zh"], "合成测试星域")
        manifest = json.loads((self.root / "out/manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["localization"]["systemNames"],
                         {"total": 3, "translated": 1, "differentFromEnglish": 1})
        self.assertEqual(manifest["localization"]["fallbackLanguage"], "en")

    def test_missing_and_blank_chinese_names_are_not_fabricated(self):
        records = fixture()
        records["types"][0]["name"]["zh"] = "  "
        records["types"][1]["name"]["zh"] = None
        catalogue = self.catalogue_for(records)
        self.assertNotIn("name_zh", catalogue["ships"][0])
        self.assertNotIn("name_zh", catalogue["modules"][0])

    def test_market_hierarchy_retains_ancestors_prunes_unused_and_keeps_unclassified(self):
        records = fixture()
        records["marketGroups"] += [
            {"_key": 2, "parentGroupID": 1, "name": {"en": "Synthetic Class", "zh": "合成分类"}},
            {"_key": 3, "parentGroupID": 2, "name": {"en": "Synthetic Family"}},
            {"_key": 4, "parentGroupID": 1, "name": {"en": "Unused Synthetic Branch"}},
        ]
        records["types"][0]["marketGroupID"] = 3
        catalogue = self.catalogue_for(records)
        self.assertEqual(catalogue["ships"][0]["market_group_id"], 3)
        self.assertNotIn("market_group_id", catalogue["modules"][0])
        self.assertEqual([g["id"] for g in catalogue["market_groups"]], [1, 2, 3])
        self.assertIsNone(catalogue["market_groups"][0]["parent_id"])
        self.assertEqual(catalogue["market_groups"][1]["name_zh"], "合成分类")
        self.assertEqual(catalogue["market_groups"][2]["parent_id"], 2)

    def test_missing_market_parent_and_cycles_fail_before_output(self):
        for parent, expected in ((999, "Missing referenced market group"), (2, "Cycle")):
            with self.subTest(parent=parent):
                records = fixture()
                records["marketGroups"].append({"_key": 2, "parentGroupID": parent,
                                                 "name": {"en": "Synthetic Broken Branch"}})
                records["types"][0]["marketGroupID"] = 2
                write_fixture(self.source, records)
                with self.assertRaisesRegex(ValueError, expected):
                    build_sde.convert(self.source, self.root / "broken-out")
                self.assertFalse((self.root / "broken-out").exists())

    def test_system_details_preserve_separate_raw_classes_and_explicit_planet_count(self):
        records = fixture()
        records["mapConstellations"][0]["name"]["zh"] = "合成测试星座"
        records["mapConstellations"][0]["wormholeClassID"] = 7
        records["mapSolarSystems"][0].update(starID=1001, planetIDs=[], securityClass="B", wormholeClassID=8)
        self.catalogue_for(records)
        universe = json.loads((self.root / "out/universe.json").read_text(encoding="utf-8"))
        one, two = universe["systems"][:2]
        self.assertEqual(one["constellation_id"], 2001)
        self.assertEqual(one["constellation_name"], "Synthetic Constellation")
        self.assertEqual(one["constellation_name_zh"], "合成测试星座")
        self.assertEqual(one["security_class"], "B")
        self.assertEqual(one["wormhole_class_id"], 8)
        self.assertEqual(one["constellation_wormhole_class_id"], 7)
        self.assertEqual(one["planet_count"], 0)
        self.assertEqual(one["star_spectral_class"], "SYNTHETIC")
        self.assertNotIn("planet_count", two)  # missing is not invented zero
        self.assertNotIn("wormhole_class_id", two)  # no guessed parent inheritance
        self.assertNotIn("star_spectral_class", two)

    def test_missing_constellation_mismatched_region_and_star_are_rejected(self):
        for problem in ("constellation", "region", "star"):
            with self.subTest(problem=problem):
                records = fixture()
                if problem == "constellation":
                    records["mapSolarSystems"][0]["constellationID"] = 999
                elif problem == "region":
                    records["mapConstellations"][0]["regionID"] = 999
                else:
                    records["mapSolarSystems"][1]["starID"] = 1001
                write_fixture(self.source, records)
                with self.assertRaises(ValueError):
                    build_sde.convert(self.source, self.root / "broken-details")
                self.assertFalse((self.root / "broken-details").exists())


if __name__ == "__main__":
    unittest.main()
