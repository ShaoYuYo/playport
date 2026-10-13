#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Checksum final native outputs so Swift-only CI retries can start at app.

No object directories, toolchains, user data or app source are cached here.
The Actions key must cover native inputs; this manifest verifies every byte
and rejects incomplete snapshots before any stage is skipped.
"""
import argparse
import hashlib
import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MANIFEST = Path('.work/runtime-checkpoint.json')
ROOTS = [
    'app/Staged', 'app/Sources/S1Probe/Runtime', 'app/artifacts.tsv',
    'build/generated', '.work/run/dxmt-patched/pe',
    'app/Sources/WinIOS/Winios.m', 'app/Sources/WinIOS/WiniosGamepad.c',
    'app/Sources/WinIOS/IOSDisplayShim.m', 'app/Sources/WinIOS/include/Winios.h',
    'app/Sources/WinIOS/include/WiniosGamepad.h', 'app/Sources/WinIOS/include/IOSDisplayShim.h',
]

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def files(repo):
    found = {}
    for root in ROOTS:
        path = repo / root
        if not path.exists():
            raise ValueError(f'missing native checkpoint output: {root}')
        entries = [path] if path.is_file() else sorted(path.rglob('*'))
        for p in entries:
            if p.is_symlink() and not p.resolve().is_relative_to(repo.resolve()):
                raise ValueError(f'checkpoint symlink leaves repository: {p}')
            if p.is_file():
                found[str(p.relative_to(repo))] = [p.stat().st_size, digest(p)]
    if not found:
        raise ValueError('empty native checkpoint')
    return found

def save(repo):
    payload = {'version': 1, 'files': files(repo)}
    (repo / MANIFEST).parent.mkdir(parents=True, exist_ok=True)
    (repo / MANIFEST).write_text(json.dumps(payload, sort_keys=True, indent=2) + '\n')
    print(f"Native checkpoint: {len(payload['files'])} files checksummed before app compilation.")

def verify(repo):
    payload = json.loads((repo / MANIFEST).read_text())
    if payload.get('version') != 1 or payload.get('files') != files(repo):
        raise ValueError('native checkpoint checksum/file-set mismatch; rebuild runtime')
    print(f"Native checkpoint verified: {len(payload['files'])} files; resume at app.")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['save', 'verify'])
    args = parser.parse_args()
    try:
        {'save': save, 'verify': verify}[args.command](REPO)
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as e:
        parser.exit(1, f'{e}\n')
