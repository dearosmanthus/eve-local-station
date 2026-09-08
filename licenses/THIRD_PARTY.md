# Third-party provenance and license archive

| Component | Usage | License / archive |
|---|---|---|
| Original EVE Local Station code | Application and tools | ../LICENSE (MIT) |
| Embers-of-the-Fire/eve-fit-os | Vendored local native runtime | MIT OR Apache-2.0, eve-fit-os-MIT.txt and eve-fit-os-APACHE-2.0.txt; pinned revision and documented build patch in ../native |
| Flutter 3.35.7 / Dart 3.9.2 | Client SDK and runtime | Flutter-BSD-3-Clause.txt; dart/inventory.json and archived package licenses; Flutter creates APK NOTICES for bundled SDK/Dart dependencies |
| Rust crates | Engine and build dependencies | cargo/inventory.json plus archived license files, generated from Cargo.lock |
| pyfa | Separate development reference only, no code/data/runtime shipped from pyfa | pyfa-GPL-3.0.txt, ../docs/PYFA.md |
| CCP Tranquility SDE | Independently obtained static catalogue/universe and Dogma/effect PB2 data | CCP-Developer-License-Agreement.html and CCP provenance notice; NOT covered by our MIT license |
| Android / Gradle tooling | Development only | Original tool distributions retain notices; Gradle-LICENSE.txt, Gradle wrapper is Apache-2.0 |

Official source links: [eve-fit-os](https://github.com/Embers-of-the-Fire/eve-fit-os), [Flutter](https://github.com/flutter/flutter/tree/3.35.7), [pyfa](https://github.com/pyfa-org/Pyfa), [CCP SDE documentation](https://developers.eveonline.com/docs/services/static-data/), [Gradle license](https://github.com/gradle/gradle/blob/v8.12.0/LICENSE).

Cargo inventory includes build-only packages (for example protoc-bin-vendored).
Some build-tool packages publish a license identifier without including a license
file in their crate archive; empty `files` entries record that fact rather than
inventing license texts. Protoc tools are not packaged into the Android runtime.
The original crate license is the project-root MIT license.

The historical EVE Space Station APK is not redistributed. None of its DEX,
native libraries, database, graphics, translations or extracted assets are used.
The launcher icon and interface geometry in this repository were created for this
project. No copyrighted EVE ship renders or copied logos are included.
