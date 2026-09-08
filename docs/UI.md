# Flutter client and interaction

The Android-first client is an original compact dark interface. It uses Flutter Material icons; it does not contain assets, code, screenshots or extracted graphics from the reference APK.

## 0.5 compact star map

- Ordinary stars use a fixed 1 dp screen radius, independent of zoom; selected systems and route endpoints have a distinct ring. A 20 dp screen hit radius makes the small marks easy to select.
- Geometry and a spatial index are built when the universe or region changes. Camera changes repaint the viewport without rebuilding the page. Overview edges and star clouds are batched; close views query nearby geometry. Screen-sized labels use a bounded layout cache and collision avoidance.
- Zoom buttons, animated location changes and a full-route view complement touch gestures. Starting a gesture stops camera animation; accessibility settings can disable it. Height changes preserve the camera centre and zoom. Landscape uses the available width, and the empty fitting screen can scroll at short heights.
- Search supports Chinese, English, IDs, regions and constellations, with six recent selections during the current session. The compact selected-system card opens local details: constellation, known planet count, known stellar spectrum, English-name copy, avoidance and adjacent systems. Unknown metadata is not estimated.
- Route actions exchange endpoints, copy canonical English names and fit the complete route. A zero-jump route can focus an isolated system. Map controls can independently hide labels or gate edges.

## 0.4 copy and category selection

- Tapping an installed module opens “复制一个” and “填满剩余同类槽位”. A pure planning step fills compatible empty positions in the same rack, retaining ammunition and state, with progressive hardpoint and group-limit checks. It never replaces existing equipment. One batch produces one edit/recalculation; failures and partial batches explain why. CPU/PG remain engine-calculated constraints.
- Ship, module, charge and drone pickers browse the official SDE category tree with counts, a breadcrumb trail and back navigation. The tree is pruned to the current candidate types and compatibility setting. Unclassified types remain in their own selectable list; a flat list remains available.
- Searching is global across the current candidates, with Chinese/English names and numeric IDs. Clearing a search returns to the selected category. The Android back action clears search or navigates up before dismissing a nested picker. Category navigation does not change item identity or EFT names.
- Category assets contain no market prices or orders; the market feature remains an unimplemented abstraction. No original APK code, graphics or database is used. These are original tool-style selection screens, not a claim of pixel-for-pixel reproduction.

## 0.3 Chinese and compact layout

- Simplified Chinese is the default for application text and Flutter system menus. Official SDE Chinese labels are separate from canonical English names; search accepts either language, groups/regions and IDs. Missing translations fall back to English, while official wormhole and null-security codes remain as published.
- A 48 dp global header and 56 dp bottom navigation replace the large brand treatment. The fitting toolbar and persistent CPU/PG/DPS/EHP summary are each 52 dp. Detailed statistics, skills and diagnostics are available in a bottom sheet.
- Slot groups use 28 dp separators with 44 dp empty/equipped rows, or 52 dp rows when ammunition needs a second line. Larger fittings offer a horizontal 44 dp group filter. Long names truncate in the list and remain readable in item details.
- Saved fittings open from the fitting title as a scrollable sheet rather than a wall of chips. Selection uses stable fit IDs, so duplicate user titles remain separate records. New/save/menu controls stay accessible; existing user titles and saved record schema are preserved.
- Phone star-map endpoints share one row. Avoided systems are managed in a scrollable sheet so a long avoidance list does not displace the map. Route data and algorithms are unchanged.

## Fitting workbench

- New fitting opens the local ship catalogue. Search accepts Chinese and English item names, groups and Type IDs.
- Published SDE slot counts determine the fitting editor. Strategic cruiser subsystem families contribute their actual slot and hardpoint modifiers. Changing a subsystem preserves any now-excess modules in a visible repair section rather than deleting them. EFT import scans subsystems before evaluating earlier weapon/low-slot lines.
- Module selection defaults to compatible choices: slot, ship group/type allowlists, required ship, rig size, remaining turret/launcher hardpoints, subsystem family and module-group maximums. Ammunition filtering checks permitted groups, optional size and single-round capacity. Missing metadata remains unknown, never a made-up exclusion. CPU/PG sums are not used as static exclusions because skills and effects modify them. Turning the filter off exposes every candidate with an explanation for known incompatibilities; local/native diagnostics remain visible after selection or import.
- Module defaults and available state-menu choices follow the actual patched PB2 effect metadata interpreted by the pinned engine. Ordinary passive equipment defaults online; activatable equipment defaults active; passive-only subsystems use bridge state `offline` (upstream Passive) and are labeled 被动. Rigs with online CPU/calibration patches remain online so resource consumption is not suppressed. EFT has no state field, so its import uses these same valid defaults. Previously saved explicit invalid states are preserved with diagnostics and can be corrected using the restricted menu.
- Drone rows preserve quantities and whether a group is active. Unchecked groups are sent to the native bridge as in-bay (`online`), which the bridge maps to a passive upstream item state.
- The default skill profile is all skills V. The alternative is no trained skills. Custom individual skills, implants, boosters, fighters and fleet effects are not exposed in this first UI.
- The pinned summary abbreviates large values with k/M; the full sheet retains labeled units and precise values. A failed calculation is explicitly labeled in the summary with an entry to the cause. Strategic cruisers retain drone editing while subsystem-derived bay capacity is recalculating.
- Save writes a versioned app-private JSON file through an adjacent temporary file and atomic rename. Reopening, switching and deleting saved fittings are supported. Switching away from an edited fitting asks whether to save it. Closing the Android app before explicitly saving may lose unsaved changes.
- EFT paste/import/export uses canonical English names. Unknown items, unsupported cargo, unknown ammunition and excess modules produce an explicit preview with warnings; a partial import requires accepting that preview. EFT does not preserve module activation state, skill assumptions or active drone selection; the local JSON does.
- Native calculation is debounced and runs on a worker isolate. Only finite values actually returned by the engine are displayed: CPU/PG, DPS/volley/EHP, capacitor/endurance, HP and resistances, navigation/targeting and drone resources. Module detail sheets expose their real ranges, cycle, tracking score and ammunition flight values. Resistance fractions are shown as percentages; distances use km where labeled. Unsupported or absent statistics stay absent.
- The UI accurately scopes the independent pyfa checks to basic indicators; special effects remain subject to validation. Native warnings are translated into actionable Chinese messages, with slot positions where available. Full statistics live in a separate sheet so module editing remains close to the top.

The native library name is `libeve_local_core.so` on Android. Android provides app-private storage through MethodChannel `eve_local_station/local_storage`, method `documentsPath`. The complete five-file PB2 pack and `engine-manifest.json` are bundled under `assets/engine/`; no first-run connection or manual data placement is required.

The installer copies files sequentially into a private staging directory, flushes each file, and invokes native health verification over every complete SHA-256, engine revision and patch-ID hash. Only a verified directory is atomically published under `<documentsPath>/engine-packs/pack-<version>`. Existing caches are revalidated against the exact bundled manifest on each launch. Damaged caches are reconstructed from the APK, interrupted staging is removed, and failed upgrades preserve the prior pack. Old versions are pruned only after successful validation/promotion. Installation is serialized across concurrent calls and protected by a file lock. All installer deletions are restricted to its own direct cache children; saved fittings are elsewhere.

Release builds require a complete valid pack and display a recoverable startup error on invalid or absent data. Only an explicit non-release `ELS_ALLOW_MISSING_ENGINE_PACK=true` development build may omit the assets, with clearly labeled editing-only behavior. This opt-out is ignored in release mode. Native failure and invalid fitting errors are distinguished; no missing-data path ever downloads anything.

## Star map

- The map projects the SDE X/Z coordinates onto a pan-and-zoom canvas. It uses the real system names, security ratings and static gate edges included in the local assets.
- The initial network view shows systems with static gate connections. A region selector and system/region search can also reveal isolated and wormhole-space systems. The search sheet is virtualized and handles the complete catalogue.
- Selecting a node exposes its security, region and gate count, with actions for start, destination and avoidance. Routes and endpoints are highlighted on the canvas; route details list every system in order.
- Shortest path uses weight 1 per gate. High-security preference uses destination-node weights 1 for high security, 26 for low security and 101 for null security. It is a weighted preference, not a guarantee of an all-high-security route. An avoided source or destination is invalid; disconnected graphs return an explicit no-route state.
- The local graph is static and undirected. Temporary wormholes, player bridges, live gate camps, ship-specific restrictions and current sovereignty are outside this release.
- Route choices and the avoidance list remain in memory during this session. Fittings are the persisted user records in this version.

## Deliberate first-release limits

- Static compatibility filtering is a convenience, not a substitute for native legality/effect validation. Advanced skills editing, implants, boosters, fighters, fleet assistance and tactical damage application are not exposed in this UI.
- There is a market contract in `lib/domain/market.dart` only. There is no market implementation, navigation item, network adapter or placeholder market page.
- No accounts, sign-in, telemetry, ads, WebView, runtime network dependencies or background services are present.

## Verification

`flutter analyze` checks the entire client. `flutter test` covers weighted gate routes, avoidance and disconnected nodes; EFT interoperability and partial-import reporting; native JSON field compatibility; stored-record rejection and file round trips; pack upgrade/corruption/interruption/concurrency recovery; real SDE charge/ship/T3 compatibility; statistic units and diagnostic labels; narrow-phone creation/save/navigation; and rendering actual SDE screens at 390×844 and 1280×900.

Compact fitting tests require at least nine completely visible equipment rows at 390×844 with both 1.0 and 1.3 text scaling, check 44/52 dp row heights and 44 dp removal targets, and verify that summary position remains fixed while equipment scrolls. They exercise module and ammunition actions, filtered racks, unsaved-change protection, rename/save and canonical-English EFT copying. The capacitor-limit test uses a native-shaped result with no `capacitor_stable` field, so an unclassified simulation limit is still visible.

Set `ELS_NATIVE_LIBRARY` to a locally built matching DLL/shared library to run the real-FFI integration test. It installs the genuine packaged PB2, verifies checksums, calculates a ship, deliberately corrupts a cached file, and proves recovery. With that same environment variable, UI previews use a genuine native result for their exact Rifter fixture rather than fabricated values. Setting `ELS_PREVIEW_DIR` also writes visual QA PNGs. These are widget test renders, not emulator or physical-device captures; Windows fonts are loaded only inside tests and never copied into the app.
