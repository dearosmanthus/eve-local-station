# Tranquility offline data

The shipped catalogue and universe are derived from the **official CCP SDE build
3494416**, released **2026-09-04T11:09:51Z**. They contain real Tranquility static
data, not demo EVE names with invented statistics. No old APK content was used.

| Output | Contents |
| --- | --- |
| `app/assets/data/catalogue.json` | 423 published ships, 4,021 modules/subsystems, 154 drones, 1,017 charges |
| `app/assets/data/universe.json` | 8,490 systems and 6,989 distinct undirected stargate connections |
| `app/assets/data/manifest.json` | Source version/hash, output hashes and sizes, record counts |

The 99,092,686-byte source ZIP has SHA256:

```text
dae55c6fcb25ec2f5fc9ddb651ee81815c07b10bb20892a7955657142d3d8409
```

The archive is a build input and is not shipped in the app or source package.
The source URL is pinned below. A live `latest` lookup was verified on 2026-09-08;
the pinned build and hash make this build reproducible even when `latest` changes.
The compatibility update reuses that already cached archive without another
download. The Chinese display update also reuses the same archive. The catalogue
is now 5,090,505 bytes including its pruned category tree; the universe is
3,890,046 bytes including official constellation and star detail fields.

## Build pipeline

Python 3.10 or newer is sufficient for base conversion, which uses the standard
library. Release conversion with `--engine-pack` also reads the verified PB2
using the pinned Protobuf dependency in `tools/engine_data/requirements.txt`.
Reuse the engine builder's installed development environment; no dependency is
downloaded by the converter.
Run from the project root. The downloader is an **explicit developer command**;
it is never called from the app, the local converter, or an ordinary app launch.

```sh
python tools/data/download_sde.py --build 3494416 --output work/sde-3494416.zip --expected-sha256 dae55c6fcb25ec2f5fc9ddb651ee81815c07b10bb20892a7955657142d3d8409
python tools/data/build_sde.py --input work/sde-3494416.zip --output app/assets/data --expected-sha256 dae55c6fcb25ec2f5fc9ddb651ee81815c07b10bb20892a7955657142d3d8409 --engine-pack app/assets/engine
python -m unittest discover -s tools/tests -v
```

To adopt a later release, explicitly download a new file (omit `--build` to
resolve the official `latest.jsonl`), review its `.download.json` provenance,
convert it, and commit the reviewed generated files and updated version record.
The downloader refuses to overwrite an existing archive. Its redirects are
restricted to the official HTTPS host. Users receive data updates with a new
APK or a future explicitly local import feature, never a background download.

The converter also accepts a local directory containing the required JSONL
files. ZIP inputs are read in place without extracting paths. Directory hashes
cover required member names and bytes in sorted order; their
`sourceHashKind: required-members-sha256` deliberately differs from an archive
hash. Same input, converter version and configuration produce identical output
bytes: output has no machine paths or build timestamps. JSON uses UTF-8,
canonical key ordering and a trailing newline. Validation occurs before output
files are replaced. This is not a transaction across all three files; distribute
them together as a versioned asset set.

## Official JSONL shape

The current format uses one object per line, with `_key` carrying integer IDs.
This pipeline reads `_sde`, `categories`, `groups`, `types`, `dogmaAttributes`,
`dogmaEffects`, `typeDogma`, `marketGroups`, `mapRegions`, `mapConstellations`,
`mapSolarSystems`, `mapStars`, and `mapStargates`.

- `types.groupID` joins `groups._key`; `groups.categoryID` joins `categories._key`.
- English `name.en` is canonical for EFT text. Available official `name.zh` is
  retained as optional `name_zh`, `group_name_zh`, `category_name_zh`, and
  `region_name_zh` alongside the corresponding English fields.
- `typeDogma.dogmaAttributes` is a list of `{attributeID, value}`.
- `typeDogma.dogmaEffects` is a list containing `effectID` and `isDefault`.
- Slots come from effect names `hiPower`, `medPower`, `loPower`, `rigSlot`, and
  `subSystem`, joined via `dogmaEffects`, not inferred from item names.
- Hull slot capacities come from `hiSlots`, `medSlots`, `lowSlots`, `rigSlots`,
  and `maxSubSystems`. `base_cpu` / `base_powergrid` are unmodified requirements,
  not skill-adjusted fitted values.
- Systems use `regionID`, `securityStatus`, localized `name`, and 3D `position`.
  Gates join `solarSystemID` to `destination.solarSystemID`.

## Asset schemas (version 1)

Both files contain `schemaVersion: 1` and `provenance`, which has `source`,
`buildNumber`, `releaseDate`, `sourceSha256`, `sourceHashKind`, `synthetic`, and
`pipelineVersion`. All IDs are integers. Unknown module slots remain `null`.
The new compatibility fields are additive: `schemaVersion` remains 1 so previous
clients can ignore the additions. `pipelineVersion: 6` adds official constellation,
planet-count and star detail fields while preserving the pruned market hierarchy,
Chinese labels, compatibility and states from the verified patched engine package.

```text
catalogue:
  ships[]: type_id, name, name_zh?, group_id, group_name, category_id,
           category_name, volume?, high_slots, medium_slots, low_slots,
           rig_slots, subsystem_slots
  modules[]: type_id, name, name_zh?, group_id, group_name, category_id,
             category_name, volume?, slot_type, base_cpu, base_powergrid
  drones[] / charges[]: type_id, name, name_zh?, group_id, group_name,
                       category_id, category_name, volume?
  all type lists: market_group_id?  # optional official types.marketGroupID
  market_groups[]: id, parent_id, name, name_zh?  # roots have null parent_id

universe:
  systems[]: id, name, name_zh?, region_id, region_name, region_name_zh?, security, x, y, z
             constellation_id?, constellation_name?, constellation_name_zh?,
             security_class?, wormhole_class_id?, constellation_wormhole_class_id?,
             planet_count?, star_id?, star_spectral_class?
  gates[]: from, to   # canonical undirected edges: from < to
```

## Chinese display and English exchange

Display names come exclusively from the same official Tranquility SDE's `zh`
fields. No translations or aliases are taken from the old APK, downloaded at
runtime, or invented by the converter. Missing, null or blank Chinese values
fall back to canonical English. The manifest records coverage and separately
counts names whose Chinese field differs from English:

| Included data | Nonblank official Chinese field | Different from English |
| --- | ---: | ---: |
| Ships | 423 / 423 | 423 |
| Modules and subsystems | 4,019 / 4,021 | 4,019 |
| Drones | 154 / 154 | 136 |
| Charges | 1,017 / 1,017 | 1,017 |
| Used item groups | 280 / 280 | 279 |
| Solar systems | 8,490 / 8,490 | 1,983 |
| Used regions | 114 / 114 | 67 |

The two untranslated modules are type 84992 (`Ryhad's Modified Medium Energy
Neutralizer`) and 84993 (`Ryhad's Modified Medium Energy Nosferatu`); they remain
English. A Chinese field can intentionally contain an unchanged system code:
6,507 system names are identical in both languages, not missing translations.
Official examples include Rifter → 裂谷级, Jita → 吉他, and The Forge → 伏尔戈.

`EveType.displayName` and `groupDisplayName` provide display labels;
`Catalogue.displayName(id)` resolves a localized type label. `SolarSystem` exposes
`displayName` and `regionDisplayName`; `Universe.regionDisplayNames` and
`regionDisplayName(id)` provide region labels. Both type and system
`matchesQuery` helpers search Chinese names, English names, both group/region
names and numeric IDs, case-insensitively. Whitespace-separated search terms
must all match, so mixed Chinese/English queries work without a network service.

The existing `name`, `group`, `Catalogue.byName`, `Catalogue.name(id)` and
`Universe.regions` remain canonical English. EFT import resolves English names;
EFT export always writes English hull/module/ammo/drone identifiers. A new fit's
user-visible title uses Chinese, and that free-form title can appear in the EFT
header without changing its interoperable English ship identifier. Stored user
titles and type IDs are preserved. The Chinese update does not modify any engine
PB2 file, module state, stat, or route edge.

## Offline solar-system details

The cached SDE joins every `mapSolarSystems.constellationID` to
`mapConstellations._key`, verifies its region, and retains official English and
Chinese constellation names. All **8,490 systems** have this detail, covering
**1,184 constellations**. Every constellation has a nonblank official Chinese
field; 323 names differ from English and the rest intentionally retain codes.
No downloaded map service or name-translation service is used.

| Optional detail | Exact source | Systems with value |
| --- | --- | ---: |
| `planet_count` | Length of an explicitly present `planetIDs` array | 8,088 |
| `star_id` | `mapSolarSystems.starID`, checked against `mapStars.solarSystemID` | 8,089 |
| `star_spectral_class` | Matching `mapStars.statistics.spectralClass` text | 8,089 |
| `security_class` | System-row `securityClass` text | 5,193 |
| `wormhole_class_id` | Explicit system-row `wormholeClassID` only | 692 |
| `constellation_wormhole_class_id` | Explicit parent constellation `wormholeClassID` | 8,113 |

Absent planet arrays and stars remain unknown, not invented zero counts. An
explicit empty planet array produces zero. The spectral class is copied from
the star's statistics, without deriving a class from its type name or color.
For example, Jita is in Kimotoro / 木本呂, has eight listed planets and a star
whose official statistics specify `F1 V`.

The two `wormholeClassID` source fields remain separate. These raw IDs also occur
in ordinary known space: Jita has no system override, its constellation has ID 7,
and its textual `securityClass` is `B`. The data layer does not turn those values
into C1–C6 labels or infer inheritance. Sentinel MZ provides another explicit
case: system-row class ID 14 and parent-row class ID 1 are both retained. The existing raw
numeric `security`, rounded display behavior and route algorithm are unchanged;
raw negative security remains available to the detail UI.

`SolarSystem` adds nullable `constellationId`, `planetCount`, `starId`,
`starSpectralClass`, `securityClass`, `wormholeClassId` and
`constellationWormholeClassId`. `constellationName` is canonical English;
`constellationDisplayName` prefers official Chinese and falls back to English.
Both names join the existing bilingual search aliases. Old const constructors
and older JSON remain valid with absent details; type/system/region identities
and the gate graph are preserved. `manifest.systemDetails` records exact field
coverage, and localization coverage includes constellation names.

## Offline equipment category browsing

The same cached archive supplies `marketGroups.jsonl` (2,108 official groups).
The converter retains only categories referenced by included fitting types and
all their ancestors: **814 groups**, each with an official Chinese label. It
preserves `types.marketGroupID` as `market_group_id`, joins `parentGroupID` as
`parent_id`, and rejects missing ancestors and cycles before writing outputs.
This tree is static navigation metadata; it introduces no prices, orders,
market transactions, backend, runtime download or market-service dependency.

For example, the official Rifter branch is 舰船 → 护卫舰 → 标准护卫舰 → 米玛塔尔.
The 200mm AutoCannon II branch is 舰船装备 → 炮台和发射器 → 射弹炮台 → 自动加农炮 → 小型.
Ship classes, faction branches, weapon families and sizes follow CCP's hierarchy
without invented classification rules or a separate race-name mapping.

`Catalogue.marketGroups` maps IDs to `MarketGroup` (`id`, `parentId`, canonical
`name`, optional `nameZh`, localized `displayName`). `EveType.marketGroupId`
returns the optional leaf category. `CatalogueBrowser(catalogue, candidates)`
builds the view for the caller's currently allowed types. `childrenOf(parentId)`
returns only direct branches with candidate descendants; `pathTo(groupId)`
returns a full root-to-leaf breadcrumb; `typesIn(groupId)` and `countIn(groupId)`
include descendant candidates. Passing null selects all candidates;
`typesIn(groupId, includeDescendants: false)` selects only direct assignments.
Paths are cached within each browser view and traversed iteratively with cycle
guards. Unknown or malformed category ancestry remains available as unclassified.

**113 types have no official market group**: 3 ships, 100 modules, 9 drones and
1 charge. They are retained in the catalogue and `ungroupedTypes`, including
when the UI automatically opens a sole classified root. Examples include Capsule,
some Abyssal modules and civilian drones; absence from the market tree is not a
reason to exclude a fitting type. Older catalogue fixtures without any tree also
remain usable through this unclassified list. The converter does not change any
PB2 bytes or fitting eligibility while adding browsing metadata.

Every catalogue item now also includes `attributes`, a map of string Dogma
attribute IDs to their finite **raw SDE** values, and `effects`, a sorted list of
effect IDs. Available physical `capacity` (m³) and `mass` (kg) come from the type
record; `volume` is already retained. The extra fields below provide convenient,
auditable selectors. Missing fields mean **unknown**, not zero or incompatible.

| Scope | Additive fields | Interpretation |
| --- | --- | --- |
| Any type with the attribute | `rig_size`, `charge_size` | Positive SDE size class, present only when explicitly defined |
| Ship | `base_cpu_output`, `base_powergrid_output` | Raw tf / MW, before skills and fitted effects |
| Ship | `drone_capacity`, `drone_bandwidth`, `turret_hardpoints`, `launcher_hardpoints`, `upgrade_capacity` | Raw m³ / Mbit/s / counts / calibration |
| Module | `charge_group_ids` | Positive `chargeGroup*` entries, sorted and deduplicated |
| Module | `fit_ship_group_ids`, `fit_ship_type_ids` | Positive `canFitShipGroup*` / `canFitShipType*` entries |
| Module | `required_ship_type_id` | Separate positive `fitsToShipType` requirement, mainly subsystems |
| Module | `max_group_fitted`, `upgrade_cost` | Positive group limit when defined; raw rig calibration cost |
| Module | `requires_turret_hardpoint`, `requires_launcher_hardpoint` | Explicit `turretFitted` / `launcherFitted` effects, not inferred from names |
| Module with matching engine pack | `supported_states`, `default_state`, `max_state` | Allowed bridge states and initial state, from patched PB2 and pinned engine state rules |
| Module with matching engine pack | `has_activation_effect`, `has_overload_effect` | Patched effect-category flags; `supported_states` determines valid UI choices |
| Drone | `bandwidth_used` | Per-drone Mbit/s from `droneBandwidthUsed`; volume remains m³ |
| Subsystem | `subsystem_family` | Raw `subSystemSlot` value |
| Subsystem | `slot_modifiers`, `hardpoint_modifiers` | Signed additive slot/hardpoint impacts, gated by their explicit effects |
| Strategic cruiser hull | `subsystem_families` | Sorted distinct families found among published, hull-specific subsystems |

Treat the ship group and type lists as an **OR union**, not an intersection. A
ship matches if its group is allowed **or** its type is allowed. If both lists
are empty, they establish no restriction. `required_ship_type_id`, when present,
is an additional explicit hull requirement. Empty charge-group lists indicate
that no positive accepted groups were supplied; they do not justify inventing a
charge family or turning missing data into a universal exclusion.

Compare charge sizes only when both the module and charge provide a positive
size. In this SDE, Heavy Missile Launcher II (2410) accepts groups 385, 395 and
655 but has **no** `charge_size`; Scourge Heavy Missile (209), group 385, likewise
has no size. Requiring a size would incorrectly remove this valid combination.
200mm AutoCannon II (2889) explicitly takes size 1 and groups 83/372; EMP S (185)
has size 1/group 83. A known rig-size mismatch is definitive. A known ammo volume
larger than a known module capacity is useful initial feedback; effective engine
validation remains authoritative where fitting effects can alter a resource.

Do not filter modules merely because summed **base** CPU/PG exceeds the ship's
base output: skills, hull bonuses and fitted effects change both requirements
and output. Raw zero drone capacity/hardpoints is preserved distinctly from an
absent field. When a static condition is uncertain, keep the item selectable and
explain that the local engine must validate it.

Module state metadata is read from the **actual verified PB2**; it is deliberately
omitted if no `--engine-pack` is supplied. The state tokens are `offline`, `online`,
`active`, and `overloaded`. `offline` maps to upstream `Passive`, so a passive-only
subsystem remains fitted and its passive effects still apply. The enum order in
`calculate/item.rs` differs from raw category IDs: category 4 is Online, 1 is
Active, and 5 is Overload. Target/Area (2/3) do not raise the maximum themselves;
the presence of `capacitorNeed`, even with value zero, raises it to Active, as
specified by `calculate/pass_2.rs`. Default state is the maximum up to Active;
overload is never selected by default.

Using unpatched SDE for this decision is incorrect: effect 16 (`online`) is
raw category 1 but `onlineEffect.yaml` changes it to category 4. Engine patches
also add Online calibration effects to rigs. Verified examples in this release:
Gyrostabilizer II (519) defaults Online; 200mm AutoCannon II (2889) defaults Active
and supports Overload; Small Core Defense Field Extender I (31788) defaults Online;
Tengu Offensive - Accelerated Ejection Bay (45601) supports only Passive/offline.
Forcing a rig to Passive would omit its patched calibration contribution.

Catalogue lists sort by case-insensitive English name and then type ID. Systems
sort by ID and edges sort by the ID pair. Raw coordinates are **metres** and must
be centered/scaled for drawing. The SDE contains disconnected systems, wormhole
space and special systems. Keeping them searchable does not imply there is a
stargate route to them. Dynamic wormholes, Ansiblex bridges, filaments, jump
drives, access restrictions, gate camps, sovereignty and player structures are
not part of this graph. A high-security preference is a static route preference
and cannot represent current travel safety.

The ship list includes strategic cruisers; their base high/medium/low slot values
are zero until subsystem effects are applied. `maxSubSystems` is a raw SDE
capacity (5 on current strategic cruiser hulls), not permission to fit five
arbitrary subsystems. The new `subsystem_families` are derived from all 48
published subsystems: 125 (core), 126 (defensive), 127 (offensive), 128 (propulsion).
Only one matching-hull subsystem per family is valid. Add its signed
`slot_modifiers` (`high`, `medium`, `low`) to the base hull slots, and its
`hardpoint_modifiers` (`turret`, `launcher`) to the corresponding hardpoints.
These maps are emitted only when the subsystem has `slotModifier` or
`hardPointModifierEffect`, respectively. Similar raw attributes without the
effect are retained in `attributes` but are not presented as operational changes.
For example, Tengu Offensive - Accelerated Ejection Bay (45601) requires Tengu
(29984), occupies family 127, adds seven high slots and six launcher hardpoints;
Tengu Core - Augmented Graviton Reactor (45626), family 125, adds two medium and
two low slots. Other skills/bonuses still belong to the engine. Fighters and
structure modules are outside this first catalogue scope.

## Fitting-engine data is a separate asset

The converter normally emits `engineDataIncluded: false` until an engine pack is
explicitly supplied with `--engine-pack`. It then checks all five nonempty PB2
files against their manifest hashes, checks the server/schema/upstream revision
and matching SDE build, and records the engine-manifest hash and pack identity in
`enginePack` before setting `engineDataIncluded: true`. The currently bundled
pack has passed these checks. For a release bundle, run the data converter with
`--engine-pack app/assets/engine` after provisioning the pack. This checks package
identity and bytes; native validation and pyfa comparisons check semantics.
The catalogue's raw attributes and selector fields do not
replace Dogma effect evaluation or produce DPS/EHP/capacitor results themselves.
The pinned eve-fit-os revision
`5772f9d6238a019b71f0fb235fbeeaf1338694f5` requires `types.pb2`,
`dogmaAttributes.pb2`, `dogmaEffects.pb2`, `typeDogma.pb2`, and
`dbuffcollections.pb2`, including its upstream patches.

`tools/engine_data/build_pack.py` now adapts the same official JSONL archive to
those pinned engine fields and applies the upstream YAML patches. The archive
already contains `dbuffCollections.jsonl`; a separate FSD or localization download
is unnecessary for this adapter. It writes the independent pack to
`app/assets/engine/` with its own `engine-manifest.json`, exact upstream revision,
patch mapping and file hashes. Provenance is recorded as SDE build `3494416` and
`fsd_build: sde-3494416` to identify this SDE-derived engine input unambiguously.
See [ENGINE_DATA.md](ENGINE_DATA.md) for the build and validation details.
Raw JSONL is not directly loadable by the runtime, and a successful conversion is
not proof of pyfa parity. Independent reference measurements remain governed by
`docs/PYFA.md`; no expected values are fabricated by this data pipeline.

## Provenance, fixtures and rights

Small synthetic schema fixtures exist only inside `tools/tests/`. They have
`synthetic: true`, invented names and IDs, and are never packaged as game data.
Tests cover deterministic output, ZIP reading, effect-based slots, undirected
deduplication, isolated systems, bad hashes, dangling gates, duplicate IDs and
nonfinite coordinates. State tests also check enum ordering, zero capacitor need,
default heat behavior, and four explicitly identified real shipped module rows.
These checks validate conversion and state compatibility, not broad gameplay accuracy.

CCP owns its game data. The project code's MIT license does not relicense it.
See `licenses/CCP-NOTICE.md` and the archived developer agreement.

Primary references, verified 2026-09-08:

- [CCP static data documentation](https://developers.eveonline.com/docs/services/static-data/)
- [Pinned official JSONL archive](https://developers.eveonline.com/static-data/tranquility/eve-online-static-data-3494416-jsonl.zip)
- [Official latest build record](https://developers.eveonline.com/static-data/tranquility/latest.jsonl)
- [CCP guide to static data](https://developers.eveonline.com/docs/guides/staticdata/)
- [CCP Developer License Agreement](https://developers.eveonline.com/license-agreement)
