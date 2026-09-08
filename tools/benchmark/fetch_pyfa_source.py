#!/usr/bin/env python3
"""Explicit developer download: only the pinned 2.4MB headless reference source.

Never invoked by the app. Every downloaded file is verified against its Git blob.
Cached verified files are reused. No GUI assets, game data, or executables fetched.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    lock = json.loads(Path(__file__).with_name('pyfa-source.lock.json').read_text())

    def fetch(entry):
        name, expected = entry
        target = args.output / name
        if target.exists():
            data = target.read_bytes()
        else:
            url = f"https://raw.githubusercontent.com/pyfa-org/Pyfa/{lock['revision']}/{name}"
            with urllib.request.urlopen(url, timeout=45) as response:
                data = response.read(2_000_001)
        if hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest() != expected:
            raise ValueError(f'Pinned Git blob mismatch: {name}')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        return len(data)

    with ThreadPoolExecutor(max_workers=4) as pool:
        total = sum(pool.map(fetch, lock['files'].items()))
    print(f"Verified {len(lock['files'])} pinned files, {total} bytes")


if __name__ == '__main__':
    main()
