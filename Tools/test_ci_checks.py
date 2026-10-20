"""Exercise CI selection and shell failure propagation without launching Xcode."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from ci_test_plan import ROOT, discover_ui_tests, select_simulator, ui_shard


class CIPlanTests(unittest.TestCase):
    def test_every_repository_ui_test_runs_exactly_once_across_six_jobs(self):
        tests = discover_ui_tests()
        shards = [ui_shard(tests, f'{index}/6') for index in range(1, 7)]
        combined = [test for shard in shards for test in shard]
        self.assertEqual(sorted(combined), tests)
        self.assertEqual(len(combined), len(set(combined)))
        self.assertLessEqual(max(map(len, shards)) - min(map(len, shards)), 1)
        self.assertTrue(all(shards))

    def test_invalid_or_empty_shards_cannot_silently_skip_tests(self):
        for value in ['0/6', '7/6', '1/0', '1/100', 'abc', '1/2/3']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                ui_shard(discover_ui_tests(), value)

    def test_discovery_includes_new_files_and_rejects_ambiguous_classes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / 'PetIslandUITests'
            folder.mkdir()
            first = folder / 'First.swift'
            first.write_text('final class First: XCTestCase {\n    func testOne() {}\n}\n')
            (folder / 'Second.swift').write_text('class Second: XCTestCase {\n    func testTwo() {}\n}\n')
            self.assertEqual(discover_ui_tests(root), ['PetIslandUITests/First/testOne', 'PetIslandUITests/Second/testTwo'])
            first.write_text(first.read_text() + 'class Other: XCTestCase {}\n')
            with self.assertRaises(ValueError):
                discover_ui_tests(root)

    def test_duplicate_selectors_and_no_tests_are_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / 'PetIslandUITests'
            folder.mkdir()
            with self.assertRaises(ValueError):
                discover_ui_tests(root)
            source = 'class Same: XCTestCase {\n    func testOne() {}\n}\n'
            (folder / 'A.swift').write_text(source)
            (folder / 'B.swift').write_text(source)
            with self.assertRaises(ValueError):
                discover_ui_tests(root)

    @staticmethod
    def device(name, state='Shutdown', available=True):
        return dict(name=name, udid=name, state=state, isAvailable=available,
                    deviceTypeIdentifier='com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro')

    def test_newest_matching_runtime_wins_over_booted_older_sdk(self):
        devices = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [self.device('old', 'Booted')],
            'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [self.device('matching')],
        }}
        self.assertEqual(select_simulator(devices, '27.1'), 'matching')
        self.assertEqual(select_simulator(devices, '26.5'), 'old')
        with self.assertRaises(ValueError):
            select_simulator(devices, '18.0')

    def test_unavailable_devices_and_ipads_are_not_selected(self):
        ipad = dict(name='iPad', udid='ipad', state='Booted', deviceTypeIdentifier='iPad')
        devices = {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [
            self.device('unavailable', available=False), ipad, self.device('phone'),
        ]}}
        self.assertEqual(select_simulator(devices, '27.1'), 'phone')


class CIRunnerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.events = self.root / 'events.jsonl'
        fake = '''#!INTERPRETER
import json, os, subprocess, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['PET_FAKE_EVENTS'], 'a') as stream:
    stream.write(json.dumps([name] + args) + '\\n')
if name == 'python-check':
    if args and args[0] == 'Tools/ci_test_plan.py':
        sys.exit(subprocess.call([sys.executable] + args))
    print('validator output')
elif name == 'xcodebuild':
    print('visible build/test progress', flush=True)
    if '-version' not in args:
        sys.exit(int(os.environ.get('PET_FAKE_EXIT', '0')))
else:
    print('simulator ready')
'''.replace('INTERPRETER', sys.executable)
        for name in ['xcodebuild', 'xcrun', 'python-check']:
            path = self.bin / name
            path.write_text(fake)
            path.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(PATH=str(self.bin) + os.pathsep + self.env['PATH'],
                        PET_PYTHON=str(self.bin / 'python-check'),
                        PET_TEST_DESTINATION='platform=iOS Simulator,id=fake-simulator',
                        PET_FAKE_EVENTS=str(self.events))

    def run_check(self, mode, **changes):
        env = dict(self.env, PET_REPORT_DIR=str(self.root / ('report-' + str(len(list(self.root.iterdir()))))))
        env.update(changes)
        result = subprocess.run(['bash', str(ROOT / 'Tools/check_project.sh'), mode], cwd=ROOT,
                                env=env, capture_output=True, text=True)
        events = [json.loads(line) for line in self.events.read_text().splitlines()] if self.events.exists() else []
        return result, events, Path(env['PET_REPORT_DIR'])

    def test_unit_job_keeps_storekit_and_never_runs_ui(self):
        result, events, report = self.run_check('unit')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        command = next(event for event in events if event[:2] == ['xcodebuild', 'test'])
        self.assertIn('-only-testing:PetIslandTests', command)
        self.assertNotIn('-only-testing:PetIslandUITests', command)
        self.assertEqual(command[command.index('-scheme') + 1], 'PetIslandTips')
        self.assertEqual(command[command.index('-parallel-testing-enabled') + 1], 'NO')
        self.assertEqual(command[command.index('-test-timeouts-enabled') + 1], 'YES')
        self.assertIn('visible build/test progress', result.stdout)
        self.assertIn('visible build/test progress', (report / 'unit-tests.log').read_text())

    def test_shell_passes_all_ui_shards_as_explicit_independent_selections(self):
        found = []
        for index in range(1, 7):
            self.events.unlink(missing_ok=True)
            result, events, report = self.run_check('ui', PET_UI_SHARD=f'{index}/6')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            command = next(event for event in events if event[:2] == ['xcodebuild', 'test'])
            selected = [arg.removeprefix('-only-testing:') for arg in command if arg.startswith('-only-testing:')]
            self.assertEqual(selected, ui_shard(discover_ui_tests(), f'{index}/6'))
            self.assertTrue((report / 'ui-tests.txt').is_file())
            found.extend(selected)
        self.assertEqual(sorted(found), discover_ui_tests())

    def test_invalid_selection_stops_before_xcode_test(self):
        result, events, _ = self.run_check('ui', PET_UI_SHARD='10/6')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(event[:2] == ['xcodebuild', 'test'] for event in events))

    def test_xcode_failure_is_not_hidden_by_tee_or_success_message(self):
        result, _, report = self.run_check('unit', PET_FAKE_EXIT='65')
        self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
        self.assertNotIn('Checks passed', result.stdout)
        self.assertIn('visible build/test progress', (report / 'unit-tests.log').read_text())

    def test_all_mode_keeps_both_test_targets_and_release_validation(self):
        result, events, report = self.run_check('all')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        command = next(event for event in events if event[:2] == ['xcodebuild', 'test'])
        self.assertFalse(any(arg.startswith('-only-testing:') for arg in command))
        self.assertTrue(any(event[:3] == ['xcodebuild', 'build', 'analyze'] for event in events))
        self.assertTrue((report / 'release-bundle.log').exists())


if __name__ == '__main__':
    unittest.main()
