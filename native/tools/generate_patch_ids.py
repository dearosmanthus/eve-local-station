"""Extract pinned negative patch identifiers; requires PyYAML at build preparation only.

Equivalent to upstream sorted patches loader and the ID assignment in
data/convert/patches/{dogma_attributes,dogma_effects}.py. No CCP data needed.
"""
import argparse
import json
from pathlib import Path
import yaml

def extract(root):
    result = {"attributes": {}, "effects": {}}
    for kind in result:
        next_id = -1
        for source in sorted((root / "data/patches").glob("*.yaml")):
            for patch in yaml.safe_load(source.read_text(encoding="utf-8")).get(kind, []):
                if "new" not in patch:
                    continue
                name = patch["new"]["name"]
                item_id = patch["new"].get("id", next_id)
                if "id" not in patch["new"]:
                    next_id -= 1
                if name in result[kind] or item_id in result[kind].values():
                    raise ValueError(f"Duplicate patch identifier: {name}: {item_id}")
                result[kind][name] = item_id
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / "vendor/eve-fit-os"
    content = json.dumps(extract(root), indent=2, sort_keys=True) + "\n"
    output = root / "patch_ids.json"
    if args.check:
        if output.read_text(encoding="utf-8") != content:
            raise SystemExit("Patch mapping changed; regenerate and rebuild engine and dataset together")
        print("Pinned patch mapping matches upstream YAML")
    else:
        output.write_text(content, encoding="utf-8", newline="\n")
        print(output)
