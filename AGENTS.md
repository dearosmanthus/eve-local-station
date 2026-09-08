# Project invariants

- Android-first Flutter/Dart application, Rust local engine. Scope is fitting and static star map; market is an abstract interface only.
- No runtime network, accounts, telemetry, ads, WebView, remote images/fonts or Android network/device-access permissions in any build variant. Retain AndroidX's signature-only internal-broadcast protection. Keep app-private storage and backups disabled.
- `tools/` may download development dependencies or explicitly requested SDE archives. These tools must not be bundled or invoked by the app.
- Do not use source, binaries, database or assets extracted from the historical EVE Space Station APK.
- Never synthesize fitting statistics when engine/data are unavailable. Return and display an explicit unavailable state.
- Pin engine source and preserve license/provenance. Keep any upstream patch minimal and archived. PB2 data must match engine revision, patch IDs and file hashes.
- pyfa is an independent development reference only. Mark comparison results as unverified until actual independent reference measurements pass at matching SDE/FSD versions.
- Run relevant tests after changes: Python tools tests, native Cargo tests, Flutter analyze/test. Android delivery must pass `tools/audit_offline.py --apk ... --aapt ...` after building the Rust library.
- Do not commit toolchains, raw downloaded archives, signing keys, local.properties, build or target directories. Keep source lockfiles and transformed SDE provenance.
