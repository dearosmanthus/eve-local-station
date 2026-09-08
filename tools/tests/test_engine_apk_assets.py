import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('audit_offline', ROOT / 'tools/audit_offline.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class EngineApkAssetsTests(unittest.TestCase):
    def setUp(self):
        self.files = {name: b'fixture protobuf bytes' for name in audit.ENGINE_FILES}
        self.manifest = {'schema_version': 1, 'server': 'tranquility',
                         'upstream_revision': 'a' * 40, 'patch_ids_sha256': 'b' * 64,
                         'sde_build': '1', 'fsd_build': 'sde-1',
                         'files': {name: hashlib.sha256(data).hexdigest() for name, data in self.files.items()}}

    def check(self):
        self.files['engine-manifest.json'] = json.dumps(self.manifest).encode()
        return audit.audit_engine_pack(self.files.__getitem__, self.files, '')

    def test_all_required_bytes_verified(self):
        self.assertEqual(self.check(), [])
        self.files['types.pb2'] += b'corruption'
        self.assertTrue(any('checksum' in message for message in self.check()))

    def test_incomplete_pack_rejected(self):
        del self.files['typeDogma.pb2']
        self.assertTrue(any('lacks' in message for message in self.check()))

    def test_foreign_server_and_extra_files_rejected(self):
        self.manifest['server'] = 'serenity'
        self.assertTrue(self.check())
        self.manifest['server'] = 'tranquility'
        self.manifest['files']['extra.pb2'] = 'a' * 64
        self.assertTrue(self.check())

    def test_real_pack_is_complete(self):
        path = ROOT / 'app/assets/engine'
        self.assertEqual(audit.audit_engine_pack(lambda name: (path / name).read_bytes(),
                                               {p.name for p in path.iterdir()}, ''), [])


if __name__ == '__main__':
    unittest.main()
