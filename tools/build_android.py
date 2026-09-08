"""Build and audit the real ARM64 Android APK, optionally from local caches only.

Baseline: Flutter 3.35.7, JDK 17, SDK 36, NDK 27.0.12077973 and cargo-ndk 4.1.2.
--offline never falls back to an online dependency resolution after a cache miss.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
NDK_VERSION = '27.0.12077973'
FLUTTER_FLAGS = ['--no-version-check', '--suppress-analytics']


def run(argv: list[str], cwd: Path, environment: dict[str, str], *, plan_only=False, offline=False) -> None:
    print('> ' + subprocess.list2cmdline(argv), flush=True)
    executable = shutil.which(argv[0], path=environment.get('PATH'))
    if not executable:
        raise ValueError(f'Executable not found: {argv[0]}')
    if not plan_only:
        process_environment = dict(environment)
        if offline and Path(executable).stem == 'flutter':
            # Only the top-level Flutter process gets a local cache-miss sink.
            # Gradle must retain its original Maven repository identity so its
            # existing dependency cache remains usable under --offline.
            process_environment['FLUTTER_STORAGE_BASE_URL'] = 'http://127.0.0.1:9'
        subprocess.run([executable, *argv[1:]], cwd=cwd, env=process_environment, check=True)


def build_environment(base, offline, cargo_target_dir=None):
    environment = dict(base)
    environment['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
    environment['DART_SUPPRESS_ANALYTICS'] = 'true'
    if cargo_target_dir is not None:
        environment['CARGO_TARGET_DIR'] = str(cargo_target_dir.resolve())
    if offline:
        environment['CARGO_NET_OFFLINE'] = 'true'
        # Cache misses must fail locally, not fetch a Rust SDK ZIP.
        environment['RUSTUP_DIST_SERVER'] = 'http://127.0.0.1:9'
        environment['RUSTUP_UPDATE_ROOT'] = 'http://127.0.0.1:9'
    return environment


def cached_gradle(root: Path, gradle_home: Path) -> Path:
    properties = (root / 'app/android/gradle/wrapper/gradle-wrapper.properties').read_text(encoding='utf-8')
    match = re.search(r'gradle-(\d+(?:\.\d+)+)-(all|bin)\.zip', properties)
    if not match:
        raise ValueError('Cannot identify the pinned Gradle distribution from wrapper properties')
    version, variant = match.groups()
    distribution = gradle_home / 'wrapper/dists' / f'gradle-{version}-{variant}'
    executable = 'gradle.bat' if os.name == 'nt' else 'gradle'
    matches = sorted(distribution.glob(f'*/gradle-{version}/bin/{executable}'))
    if not matches:
        raise ValueError(f'Offline cache miss: Gradle {version} ({variant}) is not unpacked under {distribution}')
    return matches[0].resolve()


def check_flutter_cache(flutter: Path) -> None:
    cache = flutter.resolve().parent.parent / 'bin/cache'
    executable = '.exe' if os.name == 'nt' else ''
    required = [cache / 'dart-sdk/bin' / ('dart' + executable),
                cache / 'flutter_tools.snapshot', cache / 'engine.stamp']
    missing = [str(path) for path in required if not path.is_file()]
    if not any((cache / 'artifacts/engine/android-arm64-release').rglob('gen_snapshot*')):
        missing.append('cached Android ARM64 release gen_snapshot')
    if not any((cache / 'artifacts/engine').glob('*/flutter_tester*')):
        missing.append('cached host flutter_tester (needed for tests)')
    if missing:
        raise ValueError('Offline Flutter cache is incomplete: ' + ', '.join(missing)
                         + '. Prepare Flutter/Android artifacts on an unmetered connection first.')


def commands(root: Path, sdk: Path, *, offline=False, gradle=None, gradle_project_cache_dir=None):
    app = root / 'app'
    flutter = ['flutter', *FLUTTER_FLAGS]
    cargo = ['cargo', 'ndk', '-t', 'arm64-v8a', '--platform', '24', '-o',
             str(root / 'app/android/app/src/main/jniLibs'), 'build', '--release', '--lib',
             '--frozen' if offline else '--locked']
    plan = [([sys.executable, 'tools/audit_offline.py'], root), (cargo, root / 'native'),
            ([*flutter, 'pub', 'get', *(['--offline'] if offline else [])], app),
            ([*flutter, 'analyze', '--no-pub'], app),
            ([*flutter, 'test', '--no-pub'], app)]
    build = [*flutter, 'build', 'apk', '--release', '--no-pub', '--target-platform', 'android-arm64',
             '--android-project-arg=android.overridePathCheck=true']
    if offline:
        if gradle is None:
            raise ValueError('Offline build requires an already cached pinned Gradle executable')
        # Flutter 3.35.7 exposes no Gradle --offline passthrough. config-only updates
        # local.properties and plugin files, then Gradle does the same release task.
        plan.append(([*build, '--config-only'], app))
        gradle_command = [str(gradle), '--offline', '--no-daemon', '-Dfile.encoding=UTF-8',
                          '-Pandroid.overridePathCheck=true', '-Pandroid.builder.sdkDownload=false',
                          '-Ptarget-platform=android-arm64', '-Ptarget=lib/main.dart',
                          '-Pbase-application-name=android.app.Application',
                          '-Pdart-obfuscation=false', '-Ptrack-widget-creation=true', '-Ptree-shake-icons=true']
        if gradle_project_cache_dir is not None:
            gradle_command += ['--project-cache-dir', str(gradle_project_cache_dir.resolve())]
        plan.append(([*gradle_command, 'assembleRelease'], app / 'android'))
    else:
        if gradle_project_cache_dir is not None:
            build.append('--android-project-cache-dir=' + str(gradle_project_cache_dir.resolve()))
        plan.append((build, app))
    apk = app / 'build/app/outputs/flutter-apk/app-release.apk'
    aapt = sdk / 'build-tools/36.0.0' / ('aapt.exe' if os.name == 'nt' else 'aapt')
    plan.append(([sys.executable, 'tools/audit_offline.py', '--apk', str(apk), '--aapt', str(aapt)], root))
    return plan


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--offline', action='store_true', help='Use cached Cargo/pub/Gradle dependencies; cache misses fail')
    parser.add_argument('--cargo-target-dir', type=Path, help='Reuse an existing Cargo output cache; use ASCII path on Windows GNU')
    parser.add_argument('--gradle-project-cache-dir', type=Path, help='Reuse a Gradle project cache, optionally outside a Unicode path')
    parser.add_argument('--plan-only', action='store_true', help='Validate local prerequisites and print commands without building')
    args = parser.parse_args(argv)
    environment = build_environment(os.environ, args.offline, args.cargo_target_dir)
    try:
        for command in ('flutter', 'cargo', 'java'):
            if not shutil.which(command, path=environment.get('PATH')):
                raise ValueError(f'Missing {command} on PATH. See docs/BUILD.md.')
        sdk_value = environment.get('ANDROID_HOME') or environment.get('ANDROID_SDK_ROOT')
        if not sdk_value:
            raise ValueError('Set ANDROID_HOME to the installed Android SDK.')
        sdk = Path(sdk_value).resolve()
        ndk = sdk / 'ndk' / NDK_VERSION
        if not ndk.is_dir():
            raise ValueError(f'Missing NDK: {ndk}')
        environment['ANDROID_NDK_HOME'] = str(ndk)
        gradle = None
        if args.offline:
            check_flutter_cache(Path(shutil.which('flutter', path=environment.get('PATH'))))
            gradle_home = Path(environment.get('GRADLE_USER_HOME', str(Path.home() / '.gradle')))
            gradle = cached_gradle(ROOT, gradle_home)
            for relative in ('platforms/android-36/android.jar', 'build-tools/36.0.0',
                             'build-tools/35.0.0', 'cmake/3.22.1'):
                if not (sdk / relative).exists():
                    raise ValueError(f'Offline Android SDK cache miss: {sdk / relative}')
        if os.name == 'nt' and not str(ROOT).isascii() and not environment.get('CARGO_TARGET_DIR'):
            raise ValueError('For this Unicode Windows project, set --cargo-target-dir to an ASCII cache path.')
        for command, directory in commands(ROOT, sdk, offline=args.offline, gradle=gradle,
                                            gradle_project_cache_dir=args.gradle_project_cache_dir):
            run(command, directory, environment, plan_only=args.plan_only, offline=args.offline)
    except (ValueError, OSError) as error:
        parser.exit(2, f'Build prerequisites failed: {error}\n')
    except subprocess.CalledProcessError as error:
        if args.offline:
            print('Offline build stopped. No online retry was attempted; prepare the missing dependency in its existing cache.', file=sys.stderr)
        return error.returncode
    if not args.plan_only:
        print(f'APK verified: {ROOT / "app/build/app/outputs/flutter-apk/app-release.apk"}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
