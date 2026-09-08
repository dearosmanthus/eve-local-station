"""Synthetic native protocol responses test the adapter, never engine accuracy."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/benchmark"))
import capture_engine


def fixture():
    reference = {"schemaVersion": 1, "gameServer": "Tranquility", "dataVersion": "sde:synthetic;fsd:synthetic",
                 "synthetic": True, "producer": {"name": "pyfa", "version": "synthetic", "revision": "synthetic"},
                 "cases": [{"id": "synthetic-case", "input": {"nativeFit": {"ship_type_id": 9000001},
                            "damageProfile": capture_engine.OMNI, "boosters": [], "fleetEffects": [], "environment": []},
                            "metrics": {"cpu_output": {"value": 10, "unit": "tf", "absoluteTolerance": 0.01, "relativeTolerance": 0}}}]}
    manifest = {"schema_version": 1, "server": "tranquility", "sde_build": "synthetic", "fsd_build": "synthetic",
                "upstream_revision": "synthetic-revision"}
    health = {"engine_enabled": True, "data_status": "ready", "upstream_revision": "synthetic-revision"}
    calculation = {"stats": {"cpu_output": 10}, "upstream_revision": "synthetic-revision", "damage_profile": capture_engine.OMNI}
    return reference, manifest, health, calculation


class CaptureTests(unittest.TestCase):
    def call(self, reference, manifest, health, calculation):
        return capture_engine.capture(reference, manifest, Path("synthetic-data"),
                                      lambda request: health if request["op"] == "health" else calculation,
                                      "synthetic-executable-hash", allow_synthetic=True)

    def test_capture_preserves_inputs_and_provenance(self):
        reference, manifest, health, calculation = fixture()
        result = self.call(reference, manifest, health, calculation)
        self.assertTrue(result["synthetic"])
        self.assertEqual(result["cases"][0]["input"], reference["cases"][0]["input"])
        self.assertEqual(result["cases"][0]["metrics"]["cpu_output"], {"value": 10, "unit": "tf"})

    def test_rejects_unavailable_engine_pack(self):
        reference, manifest, health, calculation = fixture()
        health["data_status"] = "missing"
        with self.assertRaisesRegex(ValueError, "unavailable"):
            self.call(reference, manifest, health, calculation)

    def test_rejects_fsd_version_mismatch(self):
        reference, manifest, health, calculation = fixture()
        manifest["fsd_build"] = "different"
        with self.assertRaisesRegex(ValueError, "dataVersion"):
            self.call(reference, manifest, health, calculation)

    def test_rejects_unapplied_booster(self):
        reference, manifest, health, calculation = fixture()
        reference["cases"][0]["input"]["boosters"] = [{"type_id": 9000002}]
        with self.assertRaisesRegex(ValueError, "empty boosters"):
            self.call(reference, manifest, health, calculation)

    def test_rejects_missing_actual_metric(self):
        reference, manifest, health, calculation = fixture()
        calculation["stats"] = {}
        with self.assertRaisesRegex(ValueError, "finite number"):
            self.call(reference, manifest, health, calculation)

    def test_rejects_invalid_fit(self):
        reference, manifest, health, calculation = fixture()
        calculation["diagnostics"] = [{"severity": "error", "message": "synthetic invalid fit"}]
        with self.assertRaisesRegex(ValueError, "invalid fit"):
            self.call(reference, manifest, health, calculation)


if __name__ == "__main__":
    unittest.main()
