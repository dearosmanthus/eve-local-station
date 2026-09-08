"""Binary manifest guard: app-internal permission must remain signature-only."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('audit_offline', ROOT / 'tools/audit_offline.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
NAME = 'org.evelocalstation.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'


def declaration(name=NAME, level='0x2'):
    protection = '' if level is None else f'      A: android:protectionLevel(0x01010009)=(type 0x11){level}\n'
    return (f'    E: permission (line=11)\n'
            f'      A: android:name(0x01010003)="{name}" (Raw: "{name}")\n'
            f'{protection}')


class ApkPermissionPolicyTests(unittest.TestCase):
    def test_exact_signature_declaration_is_accepted(self):
        self.assertTrue(audit.has_signature_permission(declaration(), NAME))

    def test_missing_or_weaker_protection_is_rejected(self):
        for level in (None, '0x0', '0x1', '0x12'):
            with self.subTest(level=level):
                self.assertFalse(audit.has_signature_permission(declaration(level=level), NAME))

    def test_adjacent_foreign_permission_cannot_supply_protection(self):
        xml = declaration(level=None) + declaration(name='another.application.PERMISSION')
        self.assertFalse(audit.has_signature_permission(xml, NAME))

    def test_missing_or_duplicate_declarations_are_rejected(self):
        self.assertFalse(audit.has_signature_permission('', NAME))
        self.assertFalse(audit.has_signature_permission(declaration() + declaration(), NAME))


if __name__ == '__main__':
    unittest.main()
