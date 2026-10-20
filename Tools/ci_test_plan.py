#!/usr/bin/env python3
"""Deterministic UI shards and a simulator compatible with the selected Xcode."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def discover_ui_tests(root=ROOT):
    tests = []
    for path in sorted((root / 'PetIslandUITests').rglob('*.swift')):
        source = path.read_text()
        methods = re.findall(r'^\s+func\s+(test\w+)\s*\(', source, re.MULTILINE)
        if not methods:
            continue
        classes = re.findall(r'^\s*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b', source, re.MULTILINE)
        if len(classes) != 1:
            raise ValueError(f'{path}: expected one XCTestCase per UI test file; update test discovery before adding another class')
        tests.extend(f'PetIslandUITests/{classes[0]}/{method}' for method in methods)
    if not tests or len(tests) != len(set(tests)):
        raise ValueError('UI test discovery is empty or contains duplicate selectors')
    return sorted(tests)


def ui_shard(tests, specification):
    match = re.fullmatch(r'([1-9]\d*)/([1-9]\d*)', specification)
    if not match:
        raise ValueError('PET_UI_SHARD must be INDEX/COUNT, for example 1/6')
    index, count = map(int, match.groups())
    if not 1 <= index <= count <= len(tests):
        raise ValueError('Shard index/count would omit tests or create an empty shard')
    return tests[index - 1::count]


def select_simulator(devices, sdk_version):
    major = int(sdk_version.split('.')[0])
    candidates = []
    for runtime, entries in devices['devices'].items():
        version = re.search(r'\.iOS-(\d+)-(\d+)(?:-(\d+))?$', runtime)
        if not version or int(version[1]) != major:
            continue
        for device in entries:
            if device.get('isAvailable') is False:
                continue
            if 'iPhone' not in device.get('deviceTypeIdentifier', device['name']):
                continue
            candidates.append((tuple(int(v or 0) for v in version.groups()),
                               device['state'] == 'Booted', device['name'], device['udid']))
    if not candidates:
        raise ValueError(f'Install an iOS {major} iPhone simulator runtime matching the selected Xcode, or set PET_TEST_DESTINATION explicitly')
    return max(candidates)[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['ui', 'simulator'])
    parser.add_argument('--shard', default='1/1')
    args = parser.parse_args()
    try:
        if args.command == 'ui':
            for test in ui_shard(discover_ui_tests(), args.shard):
                print('-only-testing:' + test)
        else:
            sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True).strip()
            devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))
            print(select_simulator(devices, sdk))
    except (ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
