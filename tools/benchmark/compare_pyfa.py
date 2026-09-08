#!/usr/bin/env python3
"""Compare independently recorded pyfa metrics with local engine results.

This tool does not run, import, download, or bundle pyfa. A passing synthetic test
validates this comparator only and is never evidence of fitting-engine parity.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sys


def number(value, location):
    if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value):
        raise ValueError(f"{location}: expected a finite number")
    return value


def indexed_cases(document):
    cases = document.get("cases")
    if not isinstance(cases, list) or not cases:
        raise ValueError("Document requires a non-empty cases array")
    result = {}
    for case in cases:
        if not isinstance(case, dict):
            raise ValueError("Each case must be an object")
        key = case.get("id")
        if not isinstance(key, str) or not key or key in result:
            raise ValueError("Case ids must be unique non-empty strings")
        if not isinstance(case.get("input"), dict) or not case["input"]:
            raise ValueError(f"{key}: full, non-empty input record is required")
        if not isinstance(case.get("metrics"), dict) or not case["metrics"]:
            raise ValueError(f"{key}: a non-empty metrics object is required")
        result[key] = case
    return result


def compare(expected, actual, allow_synthetic=False):
    for label, document in (("reference", expected), ("actual", actual)):
        if not isinstance(document, dict):
            raise ValueError(f"{label}: document must be an object")
        if document.get("schemaVersion") != 1:
            raise ValueError(f"{label}: unsupported schemaVersion")
        if document.get("gameServer") != "Tranquility":
            raise ValueError(f"{label}: gameServer must be Tranquility")
        if not isinstance(document.get("dataVersion"), str) or not document["dataVersion"].strip():
            raise ValueError(f"{label}: explicit dataVersion is required")
        if not isinstance(document.get("synthetic"), bool):
            raise ValueError(f"{label}: explicit synthetic boolean is required")
        if document["synthetic"] and not allow_synthetic:
            raise ValueError(f"{label}: synthetic fixtures are not parity evidence; use --allow-synthetic for harness tests")
        producer = document.get("producer", {})
        if not isinstance(producer, dict) or any(not isinstance(producer.get(key), str) or not producer[key].strip()
                                                  for key in ("name", "version", "revision")):
            raise ValueError(f"{label}: producer name/version/revision are required")
    if expected["producer"]["name"] != "pyfa":
        raise ValueError("Reference producer must be pyfa")
    if expected["dataVersion"] != actual["dataVersion"]:
        raise ValueError("Game-data version mismatch; regenerate both sides using equivalent data")
    if expected["synthetic"] != actual["synthetic"]:
        raise ValueError("Synthetic and measured results cannot be compared")
    references, measurements = indexed_cases(expected), indexed_cases(actual)
    if references.keys() != measurements.keys():
        raise ValueError("Reference and actual case ids differ")
    checks = []
    for key in sorted(references):
        reference, measurement = references[key], measurements[key]
        if reference["input"] != measurement["input"]:
            raise ValueError(f"{key}: fitting inputs or calculation settings differ")
        if reference["metrics"].keys() != measurement["metrics"].keys():
            raise ValueError(f"{key}: metric keys differ (missing or unreviewed metrics)")
        for metric in sorted(reference["metrics"]):
            spec, observed = reference["metrics"][metric], measurement["metrics"][metric]
            if not isinstance(spec, dict) or not isinstance(observed, dict):
                raise ValueError(f"{key}/{metric}: metric must be an object")
            if not isinstance(spec.get("unit"), str) or not spec["unit"] or spec["unit"] != observed.get("unit"):
                raise ValueError(f"{key}/{metric}: units are missing or differ")
            desired = number(spec.get("value"), f"{key}/{metric}/expected")
            value = number(observed.get("value"), f"{key}/{metric}/actual")
            absolute = number(spec.get("absoluteTolerance"), f"{key}/{metric}/absoluteTolerance")
            relative = number(spec.get("relativeTolerance"), f"{key}/{metric}/relativeTolerance")
            if absolute < 0 or relative < 0:
                raise ValueError(f"{key}/{metric}: tolerances cannot be negative")
            tolerance = max(absolute, relative * abs(desired))
            delta = abs(value - desired)
            checks.append({"case": key, "metric": metric, "expected": desired,
                           "actual": value, "unit": spec["unit"], "delta": delta,
                           "allowedDelta": tolerance, "passed": delta <= tolerance})
    return {"schemaVersion": 1, "dataVersion": expected["dataVersion"],
            "synthetic": expected["synthetic"], "passed": all(c["passed"] for c in checks),
            "referenceProducer": expected["producer"], "actualProducer": actual["producer"],
            "notice": "Synthetic comparator check only" if expected["synthetic"] else "Only the listed inputs and metrics were compared",
            "checks": checks}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", required=True, type=Path)
    parser.add_argument("--actual", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--allow-synthetic", action="store_true")
    args = parser.parse_args(argv)
    try:
        expected = json.loads(args.expected.read_text(encoding="utf-8"))
        actual = json.loads(args.actual.read_text(encoding="utf-8"))
        report = compare(expected, actual, args.allow_synthetic)
    except (ValueError, KeyError, TypeError, OSError) as exc:
        print(f"Comparison refused: {exc}", file=sys.stderr)
        return 2
    rendered = json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
