#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Add the pinned missing Mac Roman NLS table to a checksummed native snapshot.

No Wine/FEX/DXMT/Mesa output is rebuilt or discarded. Reject any changed native
input outside this exact resource/positive-verifier update before reusing cache.
"""
import hashlib
import importlib.util
from pathlib import Path
import shutil
import subprocess

REPO = Path(__file__).resolve().parent.parent
PARENT = '62f9877af5225d7e11d0c6a48edfc26c0f8e37d2'
NAME = 'c_10000.nls'
SHA256 = '20128ffdabfca32cc5a5a06d101a1b3316764ee282cc1193bf0e0cc2828931b2'
SIZE = 66082
ALLOWED = {'build/refresh-nls-checkpoint.py', 'build/stages/stage-artifacts.py', 'build/verify-ipa.py'}

def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])

def validate_delta():
    if subprocess.run(['git', '-C', str(REPO), 'cat-file', '-e', PARENT + '^{commit}'], capture_output=True).returncode:
        subprocess.run(['git', '-C', str(REPO), 'fetch', '--depth=1', 'origin', PARENT], check=True)
    changed = set(git('diff', '--name-only', PARENT, '--', 'pins.lock', 'patches', 'build',
                      'app/registry', 'app/SessionRoot', 'app/UrlOpener', 'app/PlayportJIT',
                      'app/PlayportJIT-Info.plist').decode().splitlines())
    changed = {p for p in changed if not p.startswith('build/generated/')}
    if changed - ALLOWED:
        raise ValueError('unrelated native inputs changed: ' + ', '.join(sorted(changed - ALLOWED)))
    validate_resource_sources()

def validate_resource_sources():
    data = (REPO / 'app/WindowsNLS' / NAME).read_bytes()
    if len(data) != SIZE or hashlib.sha256(data).hexdigest() != SHA256:
        raise ValueError('supplemental NLS does not match the pinned Wine table')
    before = git('show', PARENT + ':build/stages/stage-artifacts.py').decode()
    expected = before.replace('ROOTS = {\n', 'ROOTS = {\n    "nls-extra": REPO / "app/WindowsNLS",\n', 1)
    expected = expected.replace('FONTS = [', 'EXTRA_NLS = ["c_10000.nls"]\n\nFONTS = [', 1)
    expected = expected.replace('    for name in FONTS:\n        add(',
                                '    for name in EXTRA_NLS:\n        add("resource", f"Runtime/nls/{name}", "nls-extra", name, "nls")\n    for name in FONTS:\n        add(', 1)
    if (REPO / 'build/stages/stage-artifacts.py').read_text() != expected:
        raise ValueError('stage delta exceeds the one supplemental NLS resource')
    before = git('show', PARENT + ':build/verify-ipa.py').decode()
    expected = before.replace('        # DXMT: both halves from the patched fork',
                               '        nls_required = {"c_932.nls", "c_936.nls", "c_950.nls", "c_10000.nls"}\n'
                               '        check(all(rt("Runtime/nls/" + name).is_file() for name in nls_required),\n'
                               '              "nls: Japanese, Chinese and requested Mac Roman tables are packaged")\n\n'
                               '        # DXMT: both halves from the patched fork', 1)
    if (REPO / 'build/verify-ipa.py').read_text() != expected:
        raise ValueError('verifier delta exceeds the additional positive NLS gate')

def refresh(repo):
    source = repo / 'app/WindowsNLS' / NAME
    data = source.read_bytes()
    if len(data) != SIZE or hashlib.sha256(data).hexdigest() != SHA256:
        raise ValueError('supplemental NLS does not match the pinned Wine table')
    target = repo / 'app/Sources/S1Probe/Runtime/nls' / NAME
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    manifest = repo / 'app/artifacts.tsv'
    lines = manifest.read_text().splitlines()
    row = '\t'.join(['resource', 'Runtime/nls/' + NAME, str(SIZE), SHA256, 'nls-extra', NAME, 'nls'])
    prior = [i for i, line in enumerate(lines) if line.split('\t')[1:2] == ['Runtime/nls/' + NAME]]
    if len(prior) > 1 or (prior and lines[prior[0]] != row):
        raise ValueError('conflicting supplemental NLS record')
    if not prior: lines.append(row)
    manifest.write_text('\n'.join(lines) + '\n')
    shutil.copyfile(manifest, repo / 'app/Sources/S1Probe/Runtime/artifacts.tsv')
    print(f'NLS checkpoint refresh: {NAME} ({SIZE} bytes); native binaries unchanged.')

if __name__ == '__main__':
    validate_delta()
    spec = importlib.util.spec_from_file_location('checkpoint', REPO / 'build/runtime-checkpoint.py')
    checkpoint = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checkpoint)
    checkpoint.verify(REPO)
    refresh(REPO)
    checkpoint.save(REPO)
    checkpoint.verify(REPO)
