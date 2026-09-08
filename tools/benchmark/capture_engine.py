#!/usr/bin/env python3
"""Capture actual metrics using a built local native CLI and genuine engine pack.

Requires a measured pyfa reference with explicit input.nativeFit and supported
context. Executes an explicitly supplied local executable, never a shell.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from compare_pyfa import compare, indexed_cases, number

UNITS = {"cpu_used": "tf", "cpu_output": "tf", "powergrid_used": "MW", "powergrid_output": "MW",
         "speed": "m/s", "ehp": "HP", "dps": "HP/s", "dps_with_reload": "HP/s",
         "drone_dps": "HP/s", "alpha": "HP", "align_time": "s"}
OMNI = {"em": 0.25, "thermal": 0.25, "kinetic": 0.25, "explosive": 0.25}
CONTEXT_KEYS = {"nativeFit", "eft", "damageProfile", "boosters", "fleetEffects", "environment"}


def capture(reference, manifest, data_path, invoke, executable_sha256, *, allow_synthetic=False):
    # Validate the reference, including numeric values, before running anything.
    # The temporary producer is only used to reuse comparator validation here.
    validation_actual = dict(reference, producer={"name": "validation", "version": "1", "revision": "1"})
    compare(reference, validation_actual, allow_synthetic)
    if manifest.get("schema_version") != 1 or manifest.get("server") != "tranquility":
        raise ValueError("Unsupported engine manifest schema/server")
    if not manifest.get("sde_build") or not manifest.get("fsd_build"):
        raise ValueError("Engine manifest requires both sde_build and fsd_build")
    data_version = f"sde:{manifest['sde_build']};fsd:{manifest['fsd_build']}"
    if reference["dataVersion"] != data_version:
        raise ValueError(f"Reference dataVersion must exactly match {data_version}")
    health = invoke({"op": "health", "data_path": str(data_path)})
    if not health.get("engine_enabled") or health.get("data_status") != "ready":
        raise ValueError("Local engine or genuine version-checked data is unavailable")
    if health.get("upstream_revision") != manifest.get("upstream_revision") or not health.get("upstream_revision"):
        raise ValueError("Native engine and dataset upstream revisions differ")
    cases = []
    for key, case in sorted(indexed_cases(reference).items()):
        context = case["input"]
        unknown = context.keys() - CONTEXT_KEYS
        if unknown:
            raise ValueError(f"{key}: capture adapter cannot apply context fields {sorted(unknown)}")
        if context.get("damageProfile") != OMNI:
            raise ValueError(f"{key}: current native adapter requires explicit 25% omni damageProfile")
        for field in ("boosters", "fleetEffects", "environment"):
            if context.get(field) != []:
                raise ValueError(f"{key}: current native adapter requires explicit empty {field}")
        fit = context.get("nativeFit")
        if not isinstance(fit, dict) or not fit:
            raise ValueError(f"{key}: input.nativeFit is required")
        for metric, spec in case["metrics"].items():
            if metric not in UNITS or spec.get("unit") != UNITS[metric]:
                raise ValueError(f"{key}: unsupported metric/unit {metric}")
        result = invoke({"op": "calculate", "data_path": str(data_path), "fit": fit})
        if result.get("upstream_revision") != health["upstream_revision"] or result.get("damage_profile") != OMNI:
            raise ValueError(f"{key}: result revision or damage profile differs")
        if any(issue.get("severity") == "error" for issue in result.get("diagnostics", [])):
            raise ValueError(f"{key}: native engine reported an invalid fit")
        stats = result.get("stats", {})
        metrics = {}
        for metric in case["metrics"]:
            metrics[metric] = {"value": number(stats.get(metric), f"{key}/{metric}"), "unit": UNITS[metric]}
        cases.append({"id": key, "input": context, "metrics": metrics,
                      "diagnostics": result.get("diagnostics", [])})
    revision = health["upstream_revision"]
    return {"schemaVersion": 1, "gameServer": "Tranquility", "dataVersion": data_version,
            "synthetic": reference["synthetic"], "producer": {"name": "eve-fit-os", "version": "git-" + revision[:12],
                                              "revision": revision, "executableSha256": executable_sha256},
            "cases": cases}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", required=True, type=Path)
    parser.add_argument("--engine-executable", required=True, type=Path, help="Built native eve_local_core CLI")
    parser.add_argument("--data", required=True, type=Path, help="Local versioned engine pack directory")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", default=60, type=float, help="Seconds per engine operation")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if args.output.exists():
        parser.error("Output exists; choose another path to preserve previous evidence")
    try:
        engine = args.engine_executable.resolve(strict=True)
        if not engine.is_file():
            raise ValueError("--engine-executable must be a local file")
        data = args.data.resolve(strict=True)
        reference = json.loads(args.reference.read_text(encoding="utf-8"))
        manifest = json.loads((data / "engine-manifest.json").read_text(encoding="utf-8"))

        def invoke(request):
            completed = subprocess.run([str(engine)], input=json.dumps(request), capture_output=True,
                                       text=True, encoding="utf-8", timeout=args.timeout, check=True,
                                       shell=False)
            envelope = json.loads(completed.stdout)
            if envelope.get("ok") is not True:
                raise ValueError(f"Native operation failed: {envelope.get('error')}")
            return envelope["result"]

        digest = hashlib.sha256(engine.read_bytes()).hexdigest()
        actual = capture(reference, manifest, data, invoke, digest)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(actual, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
        parser.exit(2, f"Capture refused: {exc}\n")
    print(f"Captured {len(actual['cases'])} cases. Run compare_pyfa.py for the comparison result.")


if __name__ == "__main__":
    main()
