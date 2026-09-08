# Independent pyfa reference

The first real cohort contains **12 fits × 11 metrics = 132 comparisons** using
CCP Tranquility SDE 3494416. Current numeric results are in
`data/benchmarks/core-report-3494416.json`; see BUILD_REPORT.md for the final
pass status. This is limited coverage, never a claim of universal pyfa parity.

pyfa is a developer reference only. No Python interpreter, pyfa source, database,
GUI, or online service is embedded in Android. This repository's SQLite adapter,
capture tools and comparator are independently written.

## Measured scope and provenance

- Reference source: pyfa EOS commit `8b04f3b271e614b3e103853b44a7851a63d79d0e`.
  The 140 selected source files total 2,434,937 bytes. Every Git blob is verified;
  calculation code is unmodified. Its GPL/LGPL notices remain in the separate
  developer checkout; the project license is archived in `licenses/`.
- Reference data: an independent SQLite conversion of the same official JSONL
  SDE, using pyfa's own database schema. It maps raw Dogma attributes/effects,
  English type/category/group names and skill prerequisites, and includes
  mass/capacity/volume/radius. It does **not** consume eve-fit-os PB2 or patches.
- Reference execution: actual EOS Fit, Character, Module and Drone objects
  calculate all output. A GUI-config placeholder prevents wx/SSO startup;
  the saved-character DB is in memory, with no existing user overrides.
- Native data: five PB2 assets generated from that SDE, with pinned upstream
  patches. The common dataVersion is `sde:3494416;fsd:sde-3494416`. Here the FSD tag
  identifies modern SDE's complete effect source; no separate FSD was downloaded.
- Inputs and measurements: `data/benchmarks/core-inputs.json`,
  `pyfa-core-3494416.json`, `engine-core-3494416.json`. Reference capture was
  rerun into a fresh database and all raw values were identical.

Cases cover empty Rifter (all0/all5), 200mm AutoCannon II + EMP S (active,
overloaded, offline), two Gyrostabilizer II stacking, 1MN Afterburner II,
5MN Microwarpdrive II, Damage Control II, Caracal + Heavy Missile Launcher II +
Scourge Heavy Missile, and Vexor + five Hobgoblin II (active and in bay).

Metrics: CPU used/output (tf), powergrid used/output (MW), speed (m/s), omni EHP
(HP), align time (s), DPS with/without reload (HP/s), drone DPS (HP/s), total
volley (HP). CPU/PG uses unrounded pyfa sums. Total volley includes active drones.
All cases use explicit 25% EM/thermal/kinetic/explosive incoming damage, no
implants, boosters, fleet or environment effects. Absolute and relative
tolerances are both 1e-6.

The first comparison exposed an adapter defect: upstream hull alpha omitted
drone volley. The regression prompted correction using computed active drone
attributes. The reference values and tolerance were not changed to hide it.

## Reproduce the independent reference

Requires Python 3.12. Downloads below are explicit developer actions. Only the
small headless source and SQLAlchemy/logbook dependencies are needed; do not
download a GUI release or a second game database.

```sh
python tools/benchmark/fetch_pyfa_source.py --output work/pyfa-reference
python -m pip install --target work/pyfa-deps SQLAlchemy==1.4.54 logbook==1.8.2
python tools/benchmark/capture_pyfa_sde.py --pyfa-source work/pyfa-reference --deps work/pyfa-deps --sde work/sde/eve-online-static-data-3494416-jsonl.zip --sde-build 3494416 --source-sha256 dae55c6fcb25ec2f5fc9ddb651ee81815c07b10bb20892a7955657142d3d8409 --work-dir work/pyfa-fresh --inputs data/benchmarks/core-inputs.json --output work/pyfa-fresh.json
```

The capture is fully offline after dependencies are prepared. It verifies the
pinned source blobs and SDE SHA256 and refuses existing output/work directories.
The small adapter currently supports only the explicit all0/all5 context above;
it rejects implants, custom skill overrides, projected effects and unknown fields.
The SDE build label must be recorded from the verified official archive provenance.

## Capture the native result and compare

```sh
cargo build --manifest-path native/Cargo.toml --locked --bin eve_local_core
python tools/benchmark/capture_engine.py --reference data/benchmarks/pyfa-core-3494416.json --engine-executable native/target/debug/eve_local_core --data app/assets/engine --output work/engine-actual.json
python tools/benchmark/compare_pyfa.py --expected data/benchmarks/pyfa-core-3494416.json --actual work/engine-actual.json --report work/parity-report.json
```

Windows uses `eve_local_core.exe` and may need an ASCII CARGO_TARGET_DIR. Native
capture checks health, data hashes, exact upstream/SDE/effect versions, explicit
context, invalid-fit diagnostics and finite metrics. It records executable SHA256.
CI repeats this native comparison using the committed independent reference.

Comparator exit codes: 0 listed checks pass, 1 numeric mismatch, 2 invalid or
incompatible inputs/provenance. A pass requires
`abs(actual-expected) <= max(absoluteTolerance,relativeTolerance*abs(expected))`.
Missing cases, metrics, units, producer revisions, changed settings and nonfinite
values are rejected. Synthetic comparator tests require `--allow-synthetic`;
they test the harness only and never count as game-calculation evidence.

## Remaining coverage

Capacitor simulation, individual resist layers and ranges are exposed by the
engine but are not part of these 132 comparisons. Expand the independent adapter
and measured cohort before claiming those are pyfa-verified. Armor stacking,
T3 full fits, special weapons, reactive armor, implants, boosters and fleet effects
also remain outside this cohort. `data/benchmark-cases.json` tracks this broader
coverage roadmap. The runtime's universal `pyfa_verified` flag stays false.
