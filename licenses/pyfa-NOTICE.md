# pyfa reference tool

Upstream: [pyfa-org/Pyfa](https://github.com/pyfa-org/Pyfa).
pyfa is licensed under GNU GPL v3 (some EOS files also retain their own LGPL
notices). It is used only as an independent developer comparison reference.
No pyfa runtime or implementation code is included in this app. Twelve actual
headless EOS measurements using the pinned source and the same official SDE
have been collected in `data/benchmarks/`. The capture adapter and comparator
in this repository are independently written.

The upstream license was archived on 2026-09-08 as `pyfa-GPL-3.0.txt` from
[commit 8b04f3b271e614b3e103853b44a7851a63d79d0e](https://github.com/pyfa-org/Pyfa/blob/8b04f3b271e614b3e103853b44a7851a63d79d0e/LICENSE).
This is also the revision used by the headless reference capture. Developer-only
source fetches are verified using `tools/benchmark/pyfa-source.lock.json`; their
copyright/license notices are retained in the separate scratch checkout. License SHA256:

```text
8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903
```

See `docs/PYFA.md` for provenance requirements, independent measurement capture,
units, tolerance rules and the measured scope. Downloaded reference source is
excluded from the Android package and source-delivery ZIP.
