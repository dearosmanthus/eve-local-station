"""Build-policy tests inspect commands and isolated fixtures, never download tools."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('build_android', ROOT / 'tools/build_android.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class AndroidBuildPolicyTests(unittest.TestCase):
    def test_offline_stages_are_frozen_without_redundant_pub_resolution(self):
        plan = build.commands(ROOT, Path('/synthetic-sdk'), offline=True, gradle=Path('/cached/gradle'))
        cargo = next(command for command, _ in plan if command[0] == 'cargo')
        self.assertIn('--frozen', cargo)
        flutter = [command for command, _ in plan if command[0] == 'flutter']
        for command in flutter:
            self.assertIn('--no-version-check', command)
            self.assertIn('--suppress-analytics', command)
            if 'get' in command:
                self.assertIn('--offline', command)
            else:
                self.assertIn('--no-pub', command)
        self.assertEqual(sum('get' in command for command in flutter), 1)
        configure = next(command for command in flutter if 'apk' in command)
        self.assertIn('--config-only', configure)
        gradle = next(command for command, _ in plan if 'assembleRelease' in command)
        self.assertIn('--offline', gradle)
        self.assertIn('-Pandroid.overridePathCheck=true', gradle)
        self.assertIn('-Ptarget-platform=android-arm64', gradle)
        self.assertIn('--apk', plan[-1][0])

    def test_offline_plan_cannot_silently_use_an_uncached_gradle_wrapper(self):
        with self.assertRaisesRegex(ValueError, 'already cached'):
            build.commands(ROOT, Path('/synthetic-sdk'), offline=True)

    def test_normal_mode_keeps_flutter_build_and_uses_supported_cache_flag(self):
        plan = build.commands(ROOT, Path('/synthetic-sdk'), gradle_project_cache_dir=Path('/synthetic-cache'))
        command = next(command for command, _ in plan if 'apk' in command)
        self.assertNotIn('--config-only', command)
        self.assertTrue(any(arg.startswith('--android-project-cache-dir=') for arg in command))
        self.assertFalse(any('assembleRelease' in command for command, _ in plan))

    def test_environment_preserves_existing_cache_locations_without_mutating_input(self):
        original = {'PATH': 'synthetic-path', 'GRADLE_USER_HOME': 'existing-gradle', 'PUB_CACHE': 'existing-pub',
                    'FLUTTER_STORAGE_BASE_URL': 'https://existing-mirror.invalid'}
        result = build.build_environment(original, True)
        self.assertEqual(result['GRADLE_USER_HOME'], 'existing-gradle')
        self.assertEqual(result['PUB_CACHE'], 'existing-pub')
        self.assertEqual(result['FLUTTER_STORAGE_BASE_URL'], original['FLUTTER_STORAGE_BASE_URL'])
        self.assertEqual(result['CARGO_NET_OFFLINE'], 'true')
        self.assertNotIn('CARGO_NET_OFFLINE', original)

    def test_flutter_cache_miss_sink_does_not_change_gradle_maven_identity(self):
        environment = build.build_environment({'PATH': 'synthetic', 'FLUTTER_STORAGE_BASE_URL': 'https://existing-mirror.invalid'}, True)
        with patch.object(build.shutil, 'which', return_value='/cached/flutter.bat'), patch.object(build.subprocess, 'run') as invoke:
            build.run(['flutter', '--no-version-check', 'test'], ROOT, environment, offline=True)
            self.assertEqual(invoke.call_args.kwargs['env']['FLUTTER_STORAGE_BASE_URL'], 'http://127.0.0.1:9')
        with patch.object(build.shutil, 'which', return_value='/cached/gradle.bat'), patch.object(build.subprocess, 'run') as invoke:
            build.run(['/cached/gradle.bat', '--offline', 'assembleRelease'], ROOT, environment, offline=True)
            self.assertEqual(invoke.call_args.kwargs['env']['FLUTTER_STORAGE_BASE_URL'], 'https://existing-mirror.invalid')

    def test_cached_gradle_must_match_pinned_wrapper_distribution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            wrapper = root / 'project/app/android/gradle/wrapper/gradle-wrapper.properties'
            wrapper.parent.mkdir(parents=True)
            wrapper.write_text('distributionUrl=https\\://services.gradle.org/distributions/gradle-8.12-all.zip\n')
            with self.assertRaisesRegex(ValueError, 'Offline cache miss'):
                build.cached_gradle(root / 'project', root / 'gradle-home')
            executable = root / 'gradle-home/wrapper/dists/gradle-8.12-all/hash/gradle-8.12/bin' / ('gradle.bat' if os.name == 'nt' else 'gradle')
            executable.parent.mkdir(parents=True)
            executable.write_text('synthetic fixture, never executed')
            self.assertEqual(build.cached_gradle(root / 'project', root / 'gradle-home'), executable.resolve())

    def test_plan_only_never_runs_a_process(self):
        with patch.object(build.shutil, 'which', return_value='/cached/flutter'), patch.object(build.subprocess, 'run') as invoke:
            build.run(['flutter', 'test'], ROOT, {}, plan_only=True, offline=True)
            invoke.assert_not_called()


if __name__ == '__main__':
    unittest.main()
