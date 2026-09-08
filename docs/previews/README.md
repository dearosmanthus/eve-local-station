# Chinese compact UI previews (0.3 / 0.4 / 0.5)

These are Flutter widget renders at 390×844 and 1280×900, not emulator or physical-device screenshots. They use the shipped Tranquility SDE and a real result from the matching local native DLL/PB2 pack.

The fitting shown is a Rifter at all skills V with three 200mm AutoCannon II loaded with EMP S, a 1MN Afterburner II and a Small Armor Repairer II, all active. The rendered CPU, powergrid, DPS, volley, EHP and speed values were calculated by the real FFI engine for precisely that fitting before rendering; no statistics were invented for the preview. The independent pyfa comparison scope remains the basic reference cases documented in the project report.

- `fitting-phone.png`: compact phone fitting editor.
- `fitting-stats-390.png`: expanded phone statistics and available detail sections.
- `fitting-wide.png`: wide fitting editor with pinned summary.
- `map-phone.png` / `map-wide.png`: static Jita→Amarr route using the bundled gate graph.

Reproduce with `ELS_NATIVE_LIBRARY` pointing to a local matching DLL/shared library and `ELS_PREVIEW_DIR` set while running `app/test/widget_test.dart`. Preview-only Windows fonts are not included in the APK.

## 0.4 category browsing and module copying

- `ship-picker.png`: official local category path Ships → Frigates → Standard Frigates, showing faction groups.
- `module-picker.png`: high-slot equipment filtered for a Vexor, at Projectile Turrets → Autocannons, showing size groups. Static compatibility does not guess skill-dependent CPU or powergrid limits.
- `module-copy.png`: a Vexor with one online Drone Link Augmentor I, showing the copy-one and fill-empty-slots actions. The visible summary is calculated by the matching real native DLL and bundled PB2 for that exact fit, at all skills V.

These new images are widget renders at 390×844, not device captures. `app/test/selection_preview_test.dart` also checks 360×720 at text scale 1.3 and searches with a simulated 260 dp keyboard inset; it does not draw an operating-system keyboard. Standalone picker previews contain genuine SDE categories and item names with no synthetic statistics. The module-copy image requires `ELS_NATIVE_LIBRARY`; setting `ELS_PREVIEW_DIR` while running this test writes the three images plus small-screen QA variants. Windows fonts remain test-only.

## 0.5 fixed-size star map

- `map05-overview.png`: the static connected-gate network, using 5,268 of the bundled 8,490 systems. Ordinary nodes have a fixed screen radius of 1 dp and a separate 20 dp touch tolerance.
- `map05-zoom10.png`: Jita at 10× zoom; ordinary nodes, selected-node radius (2.8 dp), ring (5.5 dp), line widths and label font sizes remain screen-sized.
- `map05-focused.png` / `map05-details.png`: Jita selection and its actual SDE constellation, planet count, stellar spectral class and neighboring gate systems.
- `map05-route.png`: the locally calculated Jita–Amarr route, fitted inside the viewport. The displayed 11-jump shortest route includes a low/null-security system; it is not a safety guarantee.
- `-360` variants use 360×720 with 1.3 text scaling. `-landscape` variants use 720×360 with a scrollable side panel. Details remain scrollable, so long neighbor lists can continue below the image.

Reproduce these images with `ELS_PREVIEW_DIR` and `app/test/map_preview_test.dart`. All displayed map information comes from the genuine bundled SDE; no fitting statistics or native-number placeholders are shown. These remain Flutter widget renders, not measurements or captures from a physical Android device. Geometry tests separately verify marker and line pixel dimensions across 0.25×, 1× and 10× zoom, collision-free label rectangles, cache disposal and transform-only repaints.
