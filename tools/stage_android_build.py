"""Build an audited APK from a fresh ASCII source snapshot using local caches.

Flutter 3.35.7 Windows native tools cannot reliably open Unicode project paths.
This copies portable source; it never moves/deletes the original repository.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

try:
    from .package_source import EXCLUDE_DIRS, EXCLUDE_NAMES
except ImportError:
    from package_source import EXCLUDE_DIRS, EXCLUDE_NAMES

ROOT = Path(__file__).resolve().parents[1]
EXCLUDE_SUFFIXES = {'.jks', '.keystore', '.pyc', '.apk', '.p12', '.pfx', '.pem', '.key'}
APK_RELATIVE = Path('app/build/app/outputs/flutter-apk/app-release.apk')


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def is_link(path: Path) -> bool:
    return path.is_symlink() or bool(getattr(path.lstat(), 'st_file_attributes', 0)
                                    & getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400))


def stage_source(source: Path, destination: Path) -> dict:
    source, destination = source.resolve(), destination.resolve()
    if not str(destination).isascii():
        raise ValueError('Destination must be an absolute ASCII path for Flutter native tools')
    if destination == source or source in destination.parents or destination in source.parents:
        raise ValueError('Destination must be outside the source tree and must not contain it')
    if destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
        raise ValueError('Destination must be new or an existing empty directory; no cleanup is performed')
    selected = []
    for current, directories, names in os.walk(source, followlinks=False):
        directories[:] = sorted(name for name in directories if name not in EXCLUDE_DIRS)
        for name in directories:
            if is_link(Path(current) / name):
                raise ValueError(f'Refusing source directory link: {Path(current) / name}')
        for name in sorted(names):
            path = Path(current) / name
            if (name in EXCLUDE_NAMES or path.suffix.lower() in EXCLUDE_SUFFIXES
                    or name == '.env' or name.startswith('.env.')):
                continue
            if is_link(path):
                raise ValueError(f'Refusing source file link: {path}')
            if path.is_file():
                selected.append(path.relative_to(source))
    if not (Path('tools/build_android.py') in selected and Path('app/pubspec.yaml') in selected):
        raise ValueError('Source is missing the Android builder or Flutter project')
    destination.mkdir(parents=True, exist_ok=True)
    inventory = []
    for relative in sorted(selected, key=lambda path: path.as_posix()):
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, target)
        inventory.append({'path': relative.as_posix(), 'bytes': target.stat().st_size,
                          'sha256': sha256_file(target)})
    encoded = json.dumps(inventory, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    return {'schema_version': 1, 'source_root': str(source), 'staging_root': str(destination),
            'source_snapshot_sha256': hashlib.sha256(encoded).hexdigest(),
            'snapshot_hash_format': 'sha256-canonical-json-file-inventory',
            'file_count': len(inventory), 'files': inventory, 'offline': True, 'status': 'staged'}


def write_report(path: Path, report: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False) + '\n', encoding='utf-8')


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', required=True, type=Path, help='New or empty ASCII directory outside the project')
    parser.add_argument('--offline', action='store_true', default=True,
                        help='Compatibility flag: staged builds always use local caches')
    parser.add_argument('--cargo-target-dir', type=Path)
    parser.add_argument('--gradle-project-cache-dir', type=Path)
    parser.add_argument('--plan-only', action='store_true', help='Stage and check prerequisites; do not compile or copy an APK')
    args = parser.parse_args(argv)
    destination = args.destination.resolve()
    try:
        report = stage_source(ROOT, destination)
        report_path = destination / 'work/staging-provenance.json'
        command = [sys.executable, str(destination / 'tools/build_android.py'), '--offline']
        for option in ('cargo_target_dir', 'gradle_project_cache_dir'):
            value = getattr(args, option)
            if value is not None:
                command += ['--' + option.replace('_', '-'), str(value.resolve())]
        if args.plan_only:
            command.append('--plan-only')
        report['build_command'] = command
        write_report(report_path, report)
        print(f"Staged {report['file_count']} files; snapshot SHA256 {report['source_snapshot_sha256']}", flush=True)
        result = subprocess.run(command, cwd=destination, check=False)
        if result.returncode:
            report.update(status='failed', build_exit_code=result.returncode)
            write_report(report_path, report)
            return result.returncode
        if args.plan_only:
            report['status'] = 'prerequisites-checked'
            write_report(report_path, report)
            return 0
        # build_android returns success only after its APK manifest/data audit.
        # The new snapshot excluded every build directory and every existing APK.
        built_apk = destination / APK_RELATIVE
        if not built_apk.is_file() or not built_apk.stat().st_size:
            raise ValueError('Builder returned success without a new nonempty staged APK')
        digest = sha256_file(built_apk)
        returned_apk = ROOT / APK_RELATIVE
        returned_apk.parent.mkdir(parents=True, exist_ok=True)
        temporary = returned_apk.with_name('app-release.staged.tmp')
        shutil.copy2(built_apk, temporary)
        if sha256_file(temporary) != digest:
            raise ValueError('Returned APK copy checksum mismatch; existing APK was not replaced')
        temporary.replace(returned_apk)
        report.update(status='verified', apk_sha256=digest, apk_bytes=built_apk.stat().st_size,
                      returned_apk=str(returned_apk), apk_audit='passed by staged tools/build_android.py')
        write_report(report_path, report)
        write_report(returned_apk.with_suffix('.staging.json'), report)
        print(f'Verified APK copied to {returned_apk}\nSHA256 {digest}', flush=True)
        return 0
    except (OSError, ValueError) as exc:
        parser.exit(2, f'ASCII staging failed: {exc}\n')


if __name__ == '__main__':
    raise SystemExit(main())
