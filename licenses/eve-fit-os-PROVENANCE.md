# eve-fit-os attribution and source archive

Source: <https://github.com/Embers-of-the-Fire/eve-fit-os>

Pinned revision: `5772f9d6238a019b71f0fb235fbeeaf1338694f5`.
Retrieved 2026-09-08 from the immutable GitHub source archive after git transport failed.
Downloaded archive SHA-256: `bb30a72da4c174a6de58282e3767356cdb63e7e9963804cba7e4649f3a15cca3`.
Upstream copyright: Copyright (c) 2025 Embers-of-the-Fire.
The upstream MIT and Apache-2.0 license texts are archived verbatim alongside this notice.

`native/vendor/eve-fit-os/src/`, `data/`, `efos.proto`, `efos_pb2.py`, `skills.json`,
`pyproject.toml`, and the upstream README are vendored source from this revision.
No source code or assets from the old APK have been used.

Local build changes are recorded in `eve-fit-os-build.patch`:

- `build.rs`: replace the mandatory `.env` and external `OUTPUT_DIR/json` reads with
  a checked-in negative patch-ID map; the same name-to-constant conversion is retained.
- `build.rs`: use a build-time bundled Protobuf compiler if `PROTOC` is not supplied.
- `Cargo.toml`: include the map and licenses, declare the upstream dual license,
  and replace the unused dotenv build dependency with the optional compiler package.
- `patch_ids.json`: generated from the upstream YAML in sorted filename order;
  `native/tools/generate_patch_ids.py --check` verifies the original assignment rules.

Runtime Rust source is unmodified. This adapter's original code is under the root
project MIT license. Third-party Cargo dependencies retain their own licenses;
`native/Cargo.lock` records the exact resolved versions. Game data is CCP material,
not covered by either software license. Consult the project's CCP data notice.

Verification: all 17 vendored runtime `.rs` files match the retrieved upstream
files byte-for-byte. The generated negative-ID map was also checked against the
vendored YAML with `generate_patch_ids.py --check`.

The upstream API includes `calculate`, `validate_fit`, and `Database::init_from_root`.
Its README examples predate the pinned API and must not be copied unmodified.
