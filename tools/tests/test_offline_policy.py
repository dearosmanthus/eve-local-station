"""Exercise the source guard against regressions in Android/Dart runtime policy.

Mutations are made only to isolated temporary project fixtures, never the app.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("audit_offline", ROOT / "tools/audit_offline.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

PREFIX = ('<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
          'xmlns:tools="http://schemas.android.com/tools">')


class OfflinePolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.runtime = self.root / "app/lib/main.dart"
        self.runtime.parent.mkdir(parents=True)
        self.runtime.write_text("void main() {}\n", encoding="utf-8")
        self.manifest("main", '<application android:allowBackup="false" />')

    def tearDown(self):
        self.temp.cleanup()

    def manifest(self, variant, content):
        path = self.root / f"app/android/app/src/{variant}/AndroidManifest.xml"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(PREFIX + content + "</manifest>", encoding="utf-8")

    def test_current_project_passes_source_policy(self):
        self.assertEqual(audit.audit_sources(ROOT), [])

    def test_no_android_manifest_is_a_failure(self):
        (self.root / "app/android/app/src/main/AndroidManifest.xml").unlink()
        self.assertTrue(any("No Android manifests" in error for error in audit.audit_sources(self.root)))

    def test_network_permissions_rejected_in_every_build_variant(self):
        for variant in ("main", "debug", "profile"):
            with self.subTest(variant=variant):
                self.manifest(variant, '<uses-permission android:name="android.permission.INTERNET" />')
                errors = audit.audit_sources(self.root)
                self.assertTrue(any("runtime permission" in error and variant in error for error in errors))
                self.manifest(variant, '<application android:allowBackup="false" />')

    def test_sdk_limited_permission_is_still_rejected(self):
        self.manifest("main", '<uses-permission-sdk-23 android:name="android.permission.ACCESS_NETWORK_STATE" />')
        self.assertTrue(any("runtime permission" in error for error in audit.audit_sources(self.root)))

    def test_explicit_permission_removal_is_allowed(self):
        self.manifest("main", '<uses-permission android:name="android.permission.INTERNET" tools:node="remove" />'
                              '<application android:allowBackup="false" />')
        self.assertEqual(audit.audit_sources(self.root), [])

    def test_backup_must_be_explicitly_disabled(self):
        for attributes in ('', 'android:allowBackup="true"'):
            with self.subTest(attributes=attributes):
                self.manifest("main", f'<application {attributes} />')
                self.assertTrue(any("backups must be disabled" in error for error in audit.audit_sources(self.root)))

    def test_network_webview_and_telemetry_runtime_surfaces_are_rejected(self):
        snippets = (
            "final client = HttpClient();",
            "final server = HttpServer.bind('localhost', 9000);",
            "final socket = Socket.connect('example.invalid', 443);",
            "final socket = RawSocket.connect('example.invalid', 443);",
            "final socket = ServerSocket.bind('localhost', 9000);",
            "final socket = RawServerSocket.bind('localhost', 9000);",
            "final socket = SecureSocket.connect('example.invalid', 443);",
            "final socket = SecureServerSocket.bind('localhost', 9000, context);",
            "final socket = RawSecureSocket.connect('example.invalid', 443);",
            "final socket = RawSecureServerSocket.bind('localhost', 9000, context);",
            "final socket = RawDatagramSocket.bind('localhost', 9000);",
            "final socket = WebSocket.connect('ws://example.invalid');",
            "import 'package:http/http.dart';",
            "import 'package:dio/dio.dart';",
            "import 'package:webview_flutter/webview_flutter.dart';",
            "import 'package:firebase_core/firebase_core.dart';",
            "import 'package:sentry_flutter/sentry_flutter.dart';",
            "const endpoint = 'https://example.invalid';",
            "final view = WebView();",
        )
        for snippet in snippets:
            with self.subTest(snippet=snippet):
                self.runtime.write_text(snippet + "\n", encoding="utf-8")
                self.assertTrue(any("forbidden runtime networking surface" in error
                                    for error in audit.audit_sources(self.root)))

    def test_runtime_source_scan_includes_nested_libraries(self):
        path = self.runtime.parent / "services/nested/client.dart"
        path.parent.mkdir(parents=True)
        path.write_text("final client = HttpClient();\n", encoding="utf-8")
        self.assertTrue(any("client.dart" in error for error in audit.audit_sources(self.root)))

    def test_attribution_comments_and_explicit_build_tools_are_allowed(self):
        self.runtime.write_text("// Attribution: https://developers.eveonline.com/\nvoid main() {}\n", encoding="utf-8")
        tool = self.root / "tools/data/download.py"
        tool.parent.mkdir(parents=True)
        tool.write_text("URL = 'https://developers.eveonline.com/'\n", encoding="utf-8")
        self.assertEqual(audit.audit_sources(self.root), [])


if __name__ == "__main__":
    unittest.main()
