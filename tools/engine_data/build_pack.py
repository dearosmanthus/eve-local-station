"""Build real offline engine data from the official JSONL SDE, without FSD downloads.

Only names/field layout are adapted. Gameplay modifiers come from the official
SDE and the exact pinned eve-fit-os patches. No surrogate or guessed effects.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / 'native/vendor/eve-fit-os'
REVISION = '5772f9d6238a019b71f0fb235fbeeaf1338694f5'
SOURCES = ('types', 'groups', 'categories', 'dogmaAttributes', 'dogmaEffects',
           'typeDogma', 'dbuffCollections')
DOMAINS = {'itemID', 'shipID', 'charID', 'otherID', 'structureID', 'target', 'targetID'}
FUNCTIONS = {'ItemModifier', 'LocationGroupModifier', 'LocationModifier',
             'LocationRequiredSkillModifier', 'OwnerRequiredSkillModifier', 'EffectStopper'}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha256(path: Path) -> str:
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def read_rows(archive: zipfile.ZipFile, name: str) -> dict[int, dict]:
    rows = {}
    with archive.open(name + '.jsonl') as stream:
        for number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            row = json.loads(line)
            key = row.pop('_key')
            if not isinstance(key, int) or key in rows:
                raise ValueError(f'{name}:{number}: duplicate or non-integer key {key!r}')
            rows[key] = row
    return rows


def verify_sde_identity(archive: zipfile.ZipFile, build: str) -> None:
    with archive.open('_sde.jsonl') as stream:
        metadata = [json.loads(line) for line in stream if line.strip()]
    entries = [row for row in metadata if row.get('_key') == 'sde']
    if len(entries) != 1 or str(entries[0].get('buildNumber')) != build:
        raise ValueError('Requested build differs from the official _sde.jsonl identity')


def english_name(row: dict, label: str) -> str:
    names = row['name']
    if not isinstance(names, dict) or not isinstance(names.get('en'), str):
        raise ValueError(f'{label}: official English name missing; cannot resolve engine patches')
    return names['en']


def normalize(raw: dict[str, dict[int, dict]]) -> dict[str, dict[int, dict]]:
    data = {}
    for name in ('types', 'groups', 'categories'):
        data[name] = {}
        for item_id, row in raw[name].items():
            entry = {key: value for key, value in row.items()
                     if key in ('groupID', 'categoryID', 'mass', 'capacity', 'radius', 'volume')}
            entry['name'] = english_name(row, f'{name}:{item_id}')
            data[name][item_id] = entry
    data['dogmaAttributes'] = {
        item_id: {key: row[key] for key in ('name', 'published', 'defaultValue', 'highIsGood', 'stackable')}
        for item_id, row in raw['dogmaAttributes'].items()
    }
    data['dogmaEffects'] = {
        item_id: {'effectName': row['name'], 'effectCategory': row['effectCategoryID'],
                  'modifierInfo': copy.deepcopy(row.get('modifierInfo', []))}
        for item_id, row in raw['dogmaEffects'].items()
    }
    data['typeDogma'] = {
        item_id: {'dogmaAttributes': copy.deepcopy(row.get('dogmaAttributes', [])),
                  'dogmaEffects': copy.deepcopy(row.get('dogmaEffects', []))}
        for item_id, row in raw['typeDogma'].items()
    }
    data['dbuffcollections'] = copy.deepcopy(raw['dbuffCollections'])
    return data


def source_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def apply_upstream_patches(data: dict) -> dict:
    folder = VENDOR / 'data/convert/patches'
    loader = source_module('_els_patch_loader', folder / 'loader.py')
    patches = loader.load_patches(VENDOR / 'data/patches')
    for kind, script in (('dogmaAttributes', 'dogma_attributes'),
                         ('dogmaEffects', 'dogma_effects'), ('typeDogma', 'type_dogma')):
        patch_module = source_module('_els_patch_' + script, folder / (script + '.py'))
        patch_key = {'dogmaAttributes': 'attributes', 'dogmaEffects': 'effects', 'typeDogma': 'typeDogma'}[kind]
        patch_module.patch(data[kind], patches[patch_key], data)
    import yaml
    ignored = yaml.safe_load((VENDOR / 'data/fsd-patches/ignoredDogma.yaml').read_text(encoding='utf-8'))
    for type_id in ignored:
        data['typeDogma'].pop(type_id, None)
    # The pinned DPS patch selects several probe launchers through both speed
    # and duration branches. A type's effect registration is set-like; retain
    # one copy of identical newly introduced registrations, never alter CCP
    # positive effect IDs or merge conflicting default states.
    duplicate_patch_effects = []
    for type_id, row in data['typeDogma'].items():
        seen = set()
        retained = []
        for effect in row['dogmaEffects']:
            key = (effect['effectID'], effect['isDefault'])
            if effect['effectID'] < 0 and key in seen:
                duplicate_patch_effects.append({'type_id': type_id, 'effect_id': effect['effectID']})
                continue
            seen.add(key)
            retained.append(effect)
        row['dogmaEffects'] = retained
    return {'ignored_type_dogma': ignored, 'deduplicated_upstream_patch_effects': duplicate_patch_effects}


def validate_references(data: dict) -> dict:
    errors = []
    warnings = []
    types, groups, categories = data['types'], data['groups'], data['categories']
    attributes, effects = data['dogmaAttributes'], data['dogmaEffects']
    for type_id, row in types.items():
        if row['groupID'] not in groups:
            errors.append(f'type {type_id}: missing group {row["groupID"]}')
        for key in ('mass', 'capacity', 'radius', 'volume'):
            if key in row and not math.isfinite(row[key]):
                errors.append(f'type {type_id}: non-finite {key}')
    for group_id, row in groups.items():
        if row['categoryID'] not in categories:
            errors.append(f'group {group_id}: missing category {row["categoryID"]}')
    for type_id, row in data['typeDogma'].items():
        if type_id not in types:
            errors.append(f'typeDogma {type_id}: missing type')
        seen_attrs = set()
        for attribute in row['dogmaAttributes']:
            attr = attribute['attributeID']
            if attr not in attributes:
                errors.append(f'typeDogma {type_id}: missing attribute {attr}')
            if attr in seen_attrs:
                errors.append(f'typeDogma {type_id}: duplicate attribute {attr}')
            seen_attrs.add(attr)
            if not math.isfinite(attribute['value']):
                errors.append(f'typeDogma {type_id}: non-finite attribute {attr}')
        seen_effects = set()
        for effect in row['dogmaEffects']:
            effect_id = effect['effectID']
            if effect_id not in effects:
                errors.append(f'typeDogma {type_id}: missing effect {effect_id}')
            if effect_id in seen_effects:
                errors.append(f'typeDogma {type_id}: duplicate effect {effect_id}')
            seen_effects.add(effect_id)
    effect_stoppers = 0
    for effect_id, row in effects.items():
        for modifier in row.get('modifierInfo', []):
            if modifier.get('func') not in FUNCTIONS or modifier.get('domain') not in DOMAINS:
                errors.append(f'effect {effect_id}: unsupported modifier {modifier}')
            if modifier.get('func') == 'EffectStopper':
                effect_stoppers += 1
            for key in ('modifiedAttributeID', 'modifyingAttributeID'):
                if key in modifier and modifier[key] not in attributes:
                    errors.append(f'effect {effect_id}: missing {key}={modifier[key]}')
            if 'groupID' in modifier and modifier['groupID'] not in groups:
                errors.append(f'effect {effect_id}: missing group {modifier["groupID"]}')
            if 'skillTypeID' in modifier and modifier['skillTypeID'] != -1 and modifier['skillTypeID'] not in types:
                errors.append(f'effect {effect_id}: missing skill type {modifier["skillTypeID"]}')
            if 'operation' in modifier and modifier['operation'] not in (*range(-1, 8), 9):
                errors.append(f'effect {effect_id}: unknown operation {modifier["operation"]}')
    for buff_id, row in data['dbuffcollections'].items():
        for kind in ('itemModifiers', 'locationModifiers', 'locationGroupModifiers', 'locationRequiredSkillModifiers'):
            for modifier in row.get(kind, []):
                if modifier['dogmaAttributeID'] not in attributes:
                    errors.append(f'buff {buff_id}: missing attribute {modifier["dogmaAttributeID"]}')
                if 'groupID' in modifier and modifier['groupID'] not in groups:
                    errors.append(f'buff {buff_id}: missing group {modifier["groupID"]}')
                if 'skillID' in modifier and modifier['skillID'] not in types:
                    errors.append(f'buff {buff_id}: missing skill {modifier["skillID"]}')
    expected = json.loads((VENDOR / 'patch_ids.json').read_text(encoding='utf-8'))
    for kind, table, key in (('attributes', attributes, 'name'), ('effects', effects, 'effectName')):
        actual = {row[key]: item_id for item_id, row in table.items() if item_id < 0}
        if actual != expected[kind]:
            errors.append(f'{kind}: negative patch identifiers differ from compiled engine')
    if effect_stoppers:
        warnings.append(f'{effect_stoppers} official EffectStopper modifiers remain present; pinned engine intentionally ignores their online restrictions (pass_2.rs).')
    return {'errors': errors, 'warnings': warnings, 'record_counts': {name: len(rows) for name, rows in data.items()}}


def protobuf_payloads(data: dict) -> dict[str, tuple[str, dict]]:
    """Project actual source values into the exact pinned upstream schema."""
    types = {}
    for type_id, row in data['types'].items():
        entry = {'groupID': row['groupID'], 'categoryID': data['groups'][row['groupID']]['categoryID']}
        # Preserve the upstream converter's omission rules for physical defaults.
        for key, omitted_default in (('capacity', 0.0), ('mass', 0.0), ('radius', 1.0), ('volume', 0.0)):
            if key in row and row[key] != omitted_default:
                entry[key] = row[key]
        types[type_id] = entry
    effects = {}
    for effect_id, row in data['dogmaEffects'].items():
        modifiers = [{key: value for key, value in modifier.items() if key in
                      ('domain', 'func', 'modifiedAttributeID', 'modifyingAttributeID', 'operation', 'groupID', 'skillTypeID')}
                     for modifier in row.get('modifierInfo', [])]
        effects[effect_id] = {'name': row['effectName'], 'effectCategory': row['effectCategory'], 'modifierInfo': modifiers}
    buffs = {}
    operations = {'PreAssign': 'PRE_ASSIGN', 'PreAssignment': 'PRE_ASSIGN', 'PreMul': 'PRE_MUL',
                  'PreDiv': 'PRE_DIV', 'ModAdd': 'MOD_ADD', 'ModSub': 'MOD_SUB', 'PostMul': 'POST_MUL',
                  'PostDiv': 'POST_DIV', 'PostPercent': 'POST_PERCENT', 'PostAssign': 'POST_ASSIGN',
                  'PostAssignment': 'POST_ASSIGN'}
    for buff_id, row in data['dbuffcollections'].items():
        entry = {'buffID': buff_id, 'aggregateMode': {'Maximum': 'MAXIMUM', 'Minimum': 'MINIMUM'}[row['aggregateMode']],
                 'operationName': operations[row['operationName']],
                 'showOutputValueInUI': {'ShowNormal': 'SHOW_NORMAL', 'ShowInverted': 'SHOW_INVERTED', 'Hide': 'HIDE'}[row['showOutputValueInUI']]}
        for key in ('itemModifiers', 'locationModifiers', 'locationGroupModifiers', 'locationRequiredSkillModifiers'):
            entry[key] = row.get(key, [])
        buffs[buff_id] = entry
    attributes = {key: {field: row[field] for field in ('name', 'published', 'defaultValue', 'highIsGood', 'stackable')}
                  for key, row in data['dogmaAttributes'].items()}
    return {'types': ('Types', types), 'dogmaAttributes': ('DogmaAttributes', attributes),
            'dogmaEffects': ('DogmaEffects', effects), 'typeDogma': ('TypeDogma', data['typeDogma']),
            'dbuffcollections': ('BuffCollections', buffs)}


def build_pack(archive_path: Path, build: str, converted: Path, destination: Path) -> dict:
    archive_path, converted, destination = archive_path.resolve(), converted.resolve(), destination.resolve()
    if not build.isdigit():
        raise ValueError('SDE build must be its numeric CCP build identifier')
    if destination.exists() and any(destination.iterdir()):
        raise ValueError('Destination must be empty; choose a new candidate pack to avoid overwriting live data')
    with zipfile.ZipFile(archive_path) as archive:
        verify_sde_identity(archive, build)
        raw = {name: read_rows(archive, name) for name in SOURCES}
    raw_counts = {name: len(rows) for name, rows in raw.items()}
    data = normalize(raw)
    del raw
    patch_info = apply_upstream_patches(data)
    validation = validate_references(data)
    converted.mkdir(parents=True, exist_ok=True)
    report = {'schema_version': 1, 'sde_build': build, 'fsd_build': 'sde-' + build,
              'source_archive_sha256': file_sha256(archive_path), 'source_record_counts': raw_counts,
              'upstream_revision': REVISION, **patch_info, **validation}
    (converted / 'validation.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    if validation['errors']:
        raise ValueError(f'{len(validation["errors"])} reference errors; see {converted / "validation.json"}')
    sys.path.insert(0, str(VENDOR))
    import efos_pb2
    from google.protobuf.json_format import MessageToJson, ParseDict
    protobuf_dir, json_dir = converted / 'pb2', converted / 'json'
    protobuf_dir.mkdir(exist_ok=True)
    json_dir.mkdir(exist_ok=True)
    for name, (message_name, entries) in protobuf_payloads(data).items():
        message = getattr(efos_pb2, message_name)()
        ParseDict({'entries': {str(key): value for key, value in sorted(entries.items())}}, message)
        if not message.IsInitialized():
            raise ValueError(f'{name}: required protobuf fields are missing')
        payload = message.SerializeToString(deterministic=True)
        (protobuf_dir / (name + '.pb2')).write_bytes(payload)
        (json_dir / (name + '.json')).write_text(MessageToJson(message, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
        print(f'{name}: {len(entries)} records, {len(payload):,} bytes', flush=True)
    preparer = source_module('_els_prepare_engine', ROOT / 'native/tools/prepare_engine_data.py')
    preparer.package(converted, destination, build, 'sde-' + build)
    manifest_file = destination / 'engine-manifest.json'
    manifest = json.loads(manifest_file.read_text(encoding='utf-8'))
    manifest.update({'source': 'CCP official JSONL SDE', 'source_archive_sha256': report['source_archive_sha256'],
                     'source_record_counts': raw_counts, 'reference_errors': 0,
                     'validation_warnings': validation['warnings'], 'separate_fsd_download': False})
    manifest_file.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sde', required=True, type=Path)
    parser.add_argument('--build', required=True)
    parser.add_argument('--converted', type=Path, default=ROOT / 'work/engine-converted')
    parser.add_argument('--destination', type=Path, default=ROOT / 'app/assets/engine')
    args = parser.parse_args()
    report = build_pack(args.sde, args.build, args.converted, args.destination)
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
