"""Focused safeguards for copying a build snapshot; no SDK downloads or builds."""
from pathlib import Path
import tempfile
import unittest

from tools.stage_android_build import stage_source


class AndroidStagingTests(unittest.TestCase):
    def test_staging_omits_old_outputs_caches_and_keys_and_hashes_source(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / 'source'
            files = {'tools/build_android.py': 'source builder', 'app/pubspec.yaml': 'version: 0.2.0+2',
                     'app/assets/data/catalogue.json': '{}', 'work/cache.zip': 'cache',
                     'app/build/old.apk': 'old output', 'app/android/key.properties': 'secret',
                     'release.jks': 'secret', 'local.pem': 'secret', '.env': 'secret'}
            for name, content in files.items():
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding='utf-8')
            first = stage_source(source, root / 'first')
            second = stage_source(source, root / 'second')
            self.assertEqual(first['source_snapshot_sha256'], second['source_snapshot_sha256'])
            self.assertEqual(first['file_count'], 3)
            self.assertFalse((root / 'first/app/build').exists())
            self.assertTrue((source / 'release.jks').exists())  # source is never deleted
            (source / 'app/pubspec.yaml').write_text('version: 0.2.1+3', encoding='utf-8')
            changed = stage_source(source, root / 'third')
            self.assertNotEqual(first['source_snapshot_sha256'], changed['source_snapshot_sha256'])

    def test_nonempty_unicode_and_nested_destinations_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / 'source'
            source.mkdir()
            occupied = root / 'occupied'
            occupied.mkdir()
            (occupied / 'keep.txt').write_text('preserve', encoding='utf-8')
            for target in (occupied, root / '\u4e2d\u6587', source / 'nested'):
                with self.subTest(target=target), self.assertRaises(ValueError):
                    stage_source(source, target)
            self.assertEqual((occupied / 'keep.txt').read_text(), 'preserve')


if __name__ == '__main__':
    unittest.main()
