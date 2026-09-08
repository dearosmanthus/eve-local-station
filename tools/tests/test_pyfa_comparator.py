"""Tests the comparison harness with made-up numbers, not pyfa output."""
import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("compare_pyfa", ROOT / "tools/benchmark/compare_pyfa.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def fixture():
    expected = {"schemaVersion": 1, "gameServer": "Tranquility", "dataVersion": "synthetic-1",
                "synthetic": True, "producer": {"name": "pyfa", "version": "synthetic", "revision": "synthetic"},
                "cases": [{"id": "synthetic-case", "input": {"eft": "Synthetic", "skills": "all-v"},
                           "metrics": {"cpu": {"value": 10.0, "unit": "tf", "absoluteTolerance": 0.01,
                                               "relativeTolerance": 0.001}}}]}
    actual = copy.deepcopy(expected)
    actual["producer"]["name"] = "synthetic-engine"
    return expected, actual


class ComparatorTests(unittest.TestCase):
    def test_requires_explicit_synthetic_opt_in(self):
        with self.assertRaisesRegex(ValueError, "synthetic"):
            module.compare(*fixture())

    def test_pass_and_fail_meaningful_tolerance(self):
        expected, actual = fixture()
        actual["cases"][0]["metrics"]["cpu"]["value"] = 10.009
        self.assertTrue(module.compare(expected, actual, True)["passed"])
        actual["cases"][0]["metrics"]["cpu"]["value"] = 10.011
        self.assertFalse(module.compare(expected, actual, True)["passed"])

    def test_rejects_data_mismatch(self):
        expected, actual = fixture()
        actual["dataVersion"] = "different"
        with self.assertRaisesRegex(ValueError, "version mismatch"):
            module.compare(expected, actual, True)

    def test_rejects_missing_metrics(self):
        expected, actual = fixture()
        actual["cases"][0]["metrics"]["other"] = {"value": 0, "unit": "tf"}
        with self.assertRaisesRegex(ValueError, "metric keys"):
            module.compare(expected, actual, True)

    def test_rejects_context_mismatch(self):
        expected, actual = fixture()
        actual["cases"][0]["input"]["skills"] = "all-zero"
        with self.assertRaisesRegex(ValueError, "inputs"):
            module.compare(expected, actual, True)

    def test_rejects_nonfinite_measurement(self):
        expected, actual = fixture()
        actual["cases"][0]["metrics"]["cpu"]["value"] = float("nan")
        with self.assertRaisesRegex(ValueError, "finite number"):
            module.compare(expected, actual, True)

    def test_rejects_no_cases_or_metrics(self):
        expected, actual = fixture()
        expected["cases"] = []
        with self.assertRaisesRegex(ValueError, "non-empty cases"):
            module.compare(expected, actual, True)

    def test_rejects_malformed_metric(self):
        expected, actual = fixture()
        expected["cases"][0]["metrics"]["cpu"] = "not-a-metric-object"
        with self.assertRaisesRegex(ValueError, "metric must be an object"):
            module.compare(expected, actual, True)


if __name__ == "__main__":
    unittest.main()
