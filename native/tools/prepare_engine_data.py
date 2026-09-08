"""Package genuine converted eve-fit-os data. Never downloads data or fills gaps.

Run inside the upstream converter's Python environment (protobuf required).
The converter output must contain both json/ and pb2/. Pinned negative IDs are
verified against both formats before a manifest is emitted.
"""
import argparse
import hashlib
import importlib
import json
from pathlib import Path
import sys

REVISION = "5772f9d6238a019b71f0fb235fbeeaf1338694f5"
NATIVE = Path(__file__).resolve().parents[1]
VENDOR = NATIVE / "vendor/eve-fit-os"
FILES = {
    "types.pb2": "Types",
    "dogmaAttributes.pb2": "DogmaAttributes",
    "dogmaEffects.pb2": "DogmaEffects",
    "typeDogma.pb2": "TypeDogma",
    "dbuffcollections.pb2": "BuffCollections",
}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def package(converted: Path, destination: Path, sde_build: str, fsd_build: str):
    converted, destination = converted.resolve(), destination.resolve()
    if destination == converted or converted in destination.parents:
        raise ValueError("Destination must be separate from converter output")
    if destination.exists() and any(destination.iterdir()):
        raise ValueError("Destination must be empty; previous data will not be overwritten")
    mapping_bytes = (VENDOR / "patch_ids.json").read_bytes()
    mapping = json.loads(mapping_bytes)
    sys.path.insert(0, str(VENDOR))
    proto = importlib.import_module("efos_pb2")
    payloads, counts, decoded = {}, {}, {}
    for name, message_class in FILES.items():
        payload = (converted / "pb2" / name).read_bytes()
        message = getattr(proto, message_class)()
        message.ParseFromString(payload)
        if not payload or not message.IsInitialized() or not message.entries:
            raise ValueError(f"Incomplete protobuf: {name}")
        payloads[name], counts[name], decoded[name] = payload, len(message.entries), message
    for kind, stem in [("attributes", "dogmaAttributes"), ("effects", "dogmaEffects")]:
        entries = json.loads((converted / "json" / f"{stem}.json").read_text(encoding="utf-8"))["entries"]
        names_json = {entry["name"]: int(item_id) for item_id, entry in entries.items() if int(item_id) < 0}
        names_proto = {entry.name: item_id for item_id, entry in decoded[f"{stem}.pb2"].entries.items() if item_id < 0}
        if names_json != mapping[kind] or names_proto != mapping[kind]:
            raise ValueError(f"{stem}: patch IDs differ from pinned engine; regenerate data with vendored converter")
    manifest = {
        "schema_version": 1,
        "server": "tranquility",
        "upstream_revision": REVISION,
        "patch_ids_sha256": digest(mapping_bytes),
        "sde_build": sde_build,
        "fsd_build": fsd_build,
        "files": {name: digest(payload) for name, payload in payloads.items()},
        "record_counts": counts,
        "pyfa_verified": False,
    }
    # All validation finishes before creating the deployable directory.
    destination.mkdir(parents=True, exist_ok=True)
    for name, payload in payloads.items():
        (destination / name).write_bytes(payload)
    (destination / "engine-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(manifest, indent=2))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--converted", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--sde-build", required=True)
    parser.add_argument("--fsd-build", required=True)
    args = parser.parse_args()
    try:
        package(args.converted, args.destination, args.sde_build, args.fsd_build)
    except (OSError, ValueError, ImportError) as error:
        raise SystemExit(f"Engine data not packaged: {error}") from error

if __name__ == "__main__":
    main()
