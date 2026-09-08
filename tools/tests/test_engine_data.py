"""Contract tests for adapting real SDE fields, never synthetic fit statistics."""
import importlib.util
import io
import json
from pathlib import Path
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('engine_data_build', ROOT / 'tools/engine_data/build_pack.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class EngineDataTests(unittest.TestCase):
    def test_source_build_identity_cannot_be_relabelled(self):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, 'w') as archive:
            archive.writestr('_sde.jsonl', '{"_key":"sde","buildNumber":3494416}\n')
        stream.seek(0)
        with zipfile.ZipFile(stream) as archive:
            build.verify_sde_identity(archive, '3494416')
            with self.assertRaisesRegex(ValueError, 'official _sde.jsonl identity'):
                build.verify_sde_identity(archive, '1234')

    def test_duplicate_source_identifiers_are_rejected(self):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, 'w') as archive:
            archive.writestr('types.jsonl', '{"_key":1}\n{"_key":1}\n')
        stream.seek(0)
        with zipfile.ZipFile(stream) as archive:
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                build.read_rows(archive, 'types')

    def test_current_sde_layout_preserves_effect_modifiers(self):
        modifier = {'domain': 'itemID', 'func': 'ItemModifier', 'modifiedAttributeID': 280,
                    'modifyingAttributeID': 275, 'operation': 9}
        raw = {'types': {1: {'name': {'en': 'Test ship'}, 'groupID': 2}},
               'groups': {2: {'name': {'en': 'Test group'}, 'categoryID': 6}},
               'categories': {6: {'name': {'en': 'Ship'}}},
               'dogmaAttributes': {},
               'dogmaEffects': {132: {'name': 'skillEffect', 'effectCategoryID': 0, 'modifierInfo': [modifier]}},
               'typeDogma': {1: {}}, 'dbuffCollections': {}}
        converted = build.normalize(raw)
        self.assertEqual(converted['dogmaEffects'][132], {
            'effectName': 'skillEffect', 'effectCategory': 0, 'modifierInfo': [modifier]})
        self.assertEqual(converted['typeDogma'][1], {'dogmaAttributes': [], 'dogmaEffects': []})
        self.assertEqual(converted['types'][1]['name'], 'Test ship')
        self.assertEqual(raw['types'][1]['name'], {'en': 'Test ship'})

    def test_missing_english_patch_lookup_names_fail(self):
        with self.assertRaisesRegex(ValueError, 'English name missing'):
            build.english_name({'name': {'zh': '测试'}}, 'type 1')

    def test_buff_operations_are_translated_without_changing_modifier_targets(self):
        data = {'types': {}, 'groups': {}, 'dogmaAttributes': {}, 'dogmaEffects': {}, 'typeDogma': {},
                'dbuffcollections': {42: {'aggregateMode': 'Maximum', 'operationName': 'PreAssignment',
                                          'showOutputValueInUI': 'Hide',
                                          'locationModifiers': [{'dogmaAttributeID': 37}]}}}
        _, entries = build.protobuf_payloads(data)['dbuffcollections']
        self.assertEqual(entries[42]['operationName'], 'PRE_ASSIGN')
        self.assertEqual(entries[42]['locationModifiers'], [{'dogmaAttributeID': 37}])
        self.assertEqual(entries[42]['buffID'], 42)

    def test_unknown_buff_operation_is_never_guessed(self):
        data = {'types': {}, 'groups': {}, 'dogmaAttributes': {}, 'dogmaEffects': {}, 'typeDogma': {},
                'dbuffcollections': {42: {'aggregateMode': 'Maximum', 'operationName': 'UnsupportedRule',
                                          'showOutputValueInUI': 'Hide'}}}
        with self.assertRaises(KeyError):
            build.protobuf_payloads(data)


if __name__ == '__main__':
    unittest.main()
