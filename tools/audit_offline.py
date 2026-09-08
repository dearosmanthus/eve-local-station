"""Fail closed for runtime networking and Android package permissions."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ANDROID = '{http://schemas.android.com/apk/res/android}'
TOOLS = '{http://schemas.android.com/tools}'
ENGINE_FILES = {'types.pb2', 'dogmaAttributes.pb2', 'dogmaEffects.pb2',
                'typeDogma.pb2', 'dbuffcollections.pb2'}


def audit_engine_pack(read, names, prefix: str) -> list[str]:
    """Inspect the exact bytes shipped in the APK, including every native dataset."""
    required = ENGINE_FILES | {'engine-manifest.json'}
    missing = [name for name in sorted(required) if prefix + name not in names]
    if missing:
        return ['APK lacks bundled engine data: ' + ', '.join(missing)]
    try:
        manifest = json.loads(read(prefix + 'engine-manifest.json'))
        if (manifest.get('schema_version') != 1 or manifest.get('server') != 'tranquility'
                or set(manifest.get('files', {})) != ENGINE_FILES):
            return ['Packaged engine manifest schema/server/file set is invalid']
        failures = []
        for name in sorted(ENGINE_FILES):
            payload = read(prefix + name)
            if not payload or hashlib.sha256(payload).hexdigest() != manifest['files'][name]:
                failures.append(f'Packaged engine checksum mismatch: {name}')
        if (not re.fullmatch(r'[0-9a-f]{40}', manifest.get('upstream_revision', ''))
                or not re.fullmatch(r'[0-9a-f]{64}', manifest.get('patch_ids_sha256', ''))
                or not manifest.get('sde_build') or not manifest.get('fsd_build')):
            failures.append('Packaged engine provenance is incomplete')
        return failures
    except (ValueError, TypeError, AttributeError):
        return ['Packaged engine manifest is malformed']


def has_signature_permission(xmltree: str, permission_name: str) -> bool:
    """Require exactly one matching binary-manifest declaration, flags == 0x2.

    Parse aapt element boundaries so an adjacent permission cannot provide the
    protection level for the allowed name. Unknown/missing encodings fail closed.
    """
    declarations: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    depth = -1
    for line in xmltree.splitlines():
        element = re.match(r'^(\s*)E: ([\w-]+)\b', line)
        if element:
            indentation = len(element.group(1))
            if current is not None and indentation <= depth:
                declarations.append(current)
                current = None
            if element.group(2) == 'permission':
                current, depth = {}, indentation
            continue
        if current is None or len(line) - len(line.lstrip()) != depth + 2:
            continue
        name = re.search(r'A: android:name\([^)]*\)="([^"]+)"', line)
        if name:
            current['name'] = name.group(1)
        protection = re.search(
            r'A: android:protectionLevel\([^)]*\)=\(type 0x[0-9a-fA-F]+\)0x([0-9a-fA-F]+)\s*$',
            line,
        )
        if protection:
            current['protection'] = int(protection.group(1), 16)
    if current is not None:
        declarations.append(current)
    matching = [item for item in declarations if item.get('name') == permission_name]
    return len(matching) == 1 and matching[0].get('protection') == 2


def audit_sources(root: Path = ROOT) -> list[str]:
    failures: list[str] = []
    manifests = list((root / 'app/android/app/src').rglob('AndroidManifest.xml'))
    if not manifests:
        failures.append('No Android manifests found')
    for path in manifests:
        tree = ET.parse(path)
        for node in tree.getroot():
            if node.tag.startswith('uses-permission') and node.get(TOOLS + 'node') != 'remove':
                failures.append(f'{path}: runtime permission {node.get(ANDROID + "name")}')
        for app in tree.iter('application'):
            if app.get(ANDROID + 'allowBackup') != 'false':
                failures.append(f'{path}: application backups must be disabled')
    forbidden = re.compile(r'\b(HttpClient|HttpServer|Socket|WebSocket|RawSocket|ServerSocket|RawServerSocket|SecureSocket|SecureServerSocket|RawSecureSocket|RawSecureServerSocket|RawDatagramSocket|WebView|Firebase|Sentry)\b|package:(http|dio|webview_flutter|firebase_\w+|sentry_flutter)/|(?:https?|wss?)://')
    for path in (root / 'app/lib').rglob('*.dart'):
        for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
            # URLs in attribution comments are not runtime operations.
            if line.strip().startswith('//'):
                continue
            if forbidden.search(line):
                failures.append(f'{path}:{number}: forbidden runtime networking surface')
    return failures


def audit_apk(apk: Path, aapt: Path) -> list[str]:
    failures = []
    result = subprocess.run([str(aapt), 'dump', 'permissions', str(apk)], check=True,
                            capture_output=True, text=True)
    # AndroidX adds this signature permission to protect non-exported dynamic
    # broadcasts on older Android versions. It grants no device/network access;
    # retaining it avoids weakening the library's receiver protection.
    internal_permission = 'org.evelocalstation.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
    permissions = re.findall(r"uses-permission(?:-sdk-\d+)?:\s+name='([^']+)'", result.stdout)
    for permission in permissions:
        if permission != internal_permission:
            failures.append(f'APK declares forbidden permission: {permission}')
    if internal_permission in permissions:
        package = re.search(r'^package:\s+(\S+)\s*$', result.stdout, re.MULTILINE)
        xmltree = subprocess.run(
            [str(aapt), 'dump', 'xmltree', str(apk), 'AndroidManifest.xml'],
            check=True, capture_output=True, text=True, encoding='utf-8',
        ).stdout
        if (package is None or package.group(1) != 'org.evelocalstation.app'
                or not has_signature_permission(xmltree, internal_permission)):
            failures.append('APK internal receiver permission must have its own unique signature-only declaration')
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if 'lib/arm64-v8a/libeve_local_core.so' not in names:
            failures.append('APK lacks ARM64 Rust core')
        for name in ('catalogue.json', 'universe.json', 'manifest.json'):
            if f'assets/flutter_assets/assets/data/{name}' not in names:
                failures.append(f'APK lacks {name}')
        data_root = 'assets/flutter_assets/assets/data/'
        if all(data_root + name in names for name in ('manifest.json', 'catalogue.json', 'universe.json')):
            manifest = json.loads(archive.read(data_root + 'manifest.json'))
            for name in ('catalogue.json', 'universe.json'):
                data = archive.read(data_root + name)
                expected = manifest.get('files', {}).get(name, {})
                if len(data) != expected.get('bytes') or hashlib.sha256(data).hexdigest() != expected.get('sha256'):
                    failures.append(f'Packaged SDE checksum mismatch: {name}')
        if 'assets/flutter_assets/assets/licenses/THIRD_PARTY_NOTICES.txt' not in names:
            failures.append('APK lacks local third-party license notices')
        failures += audit_engine_pack(archive.read, names, 'assets/flutter_assets/assets/engine/')
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path)
    parser.add_argument('--aapt', type=Path)
    args = parser.parse_args()
    errors = audit_sources()
    if args.apk:
        if not args.aapt:
            parser.error('--apk requires --aapt; binary manifests cannot be audited as plain text')
        errors += audit_apk(args.apk, args.aapt)
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print('PASS: offline source policy' + (' and packaged APK permissions/assets/native library' if args.apk else ' (APK not inspected)'))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
