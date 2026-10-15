#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Migrate the diagnostic checkpoint by rebuilding only the two FEX modules."""
import hashlib
import importlib.util
from pathlib import Path
import shutil
import struct
import subprocess

REPO = Path(__file__).resolve().parent.parent
# Public diagnostic source tree; works across equivalent local/API commits.
PARENT = 'f2125ddcf51161d8f09348c79c7eaf4345aafaa2'
PATCH = '0024-CPUID-use-the-synthetic-iOS-processor-index.patch'

def git(*args):
    return subprocess.check_output(['git', '-c', 'core.filemode=false', '-C', str(REPO), *args])

def main():
    allowed_inputs = {'patches/fex/series', 'patches/fex/' + PATCH,
                      'build/rebuild-ios-cpuid-checkpoint.py', 'build/test-ios-cpuid.py'}
    paths = ['pins.lock', 'patches', 'build', 'app/registry', 'app/WindowsNLS',
             'app/SessionRoot', 'app/UrlOpener', 'app/PlayportJIT', 'app/PlayportJIT-Info.plist']
    candidates = set(git('diff', '--name-only', PARENT, '--', *paths).decode().splitlines())
    candidates.update(git('ls-files', '--others', '--exclude-standard', '--', *paths).decode().splitlines())
    changed = set()
    for p in candidates:
        if p.startswith('build/generated/'): continue
        parent = subprocess.run(['git', '-C', str(REPO), 'show', PARENT + ':' + p], capture_output=True)
        actual = (REPO / p).read_bytes() if (REPO / p).is_file() else None
        if parent.returncode != 0 or parent.stdout != actual: changed.add(p)
    if changed - allowed_inputs:
        raise ValueError('unrelated native input changes: ' + ', '.join(sorted(changed - allowed_inputs)))
    series = git('show', PARENT + ':patches/fex/series') + PATCH.encode() + b'\n'
    if (REPO / 'patches/fex/series').read_bytes() != series:
        raise ValueError('expected the exact CPUID patch append')
    # Validate the complete patch body against the intended, minimal change.
    patch = (REPO / 'patches/fex' / PATCH).read_text()
    if hashlib.sha256(patch.encode()).hexdigest() != '19ee470a653ccc5e29913cbd3bdd9c9a39350df541a13ed059e9b4b823c879e5':
        raise ValueError('unexpected CPUID patch bytes')
    spec = importlib.util.spec_from_file_location('checkpoint', REPO / 'build/runtime-checkpoint.py')
    cp = importlib.util.module_from_spec(spec); spec.loader.exec_module(cp)
    cp.verify(REPO); before = cp.files(REPO)
    root = REPO / '.work/run/fex'
    subprocess.run(['bash', 'build/stages/fex.sh', str(root), 'arm64ec wow64'], cwd=REPO, check=True)
    subprocess.run(['python3', 'build/test-ios-cpuid.py', str(root / 'fex')], cwd=REPO, check=True)
    replacements = [
        # ARM64EC DLLs carry the AMD64 COFF value; fex.sh checks LLVM's
        # decoded ARM64EC identity (including the hybrid metadata).
        ('build-arm64ec/Bin/libarm64ecfex.dll', 'arm64ec-windows/xtajit64.dll', 0x8664),
        ('build-wow64/Bin/libwow64fex.dll', 'aarch64-windows/xtajit.dll', 0xaa64),
    ]
    records = REPO / 'app/artifacts.tsv'
    rows = records.read_text().splitlines()
    allowed_outputs = {'app/artifacts.tsv', 'app/Sources/S1Probe/Runtime/artifacts.tsv'}
    for output, target, machine in replacements:
        path = root / 'fex' / output; data = path.read_bytes()
        offset = struct.unpack_from('<I', data, 60)[0]
        if data[:2] != b'MZ' or data[offset:offset+4] != b'PE\0\0' or struct.unpack_from('<H', data, offset+4)[0] != machine:
            raise ValueError('unexpected FEX image type: ' + output)
        count = 0
        for i, row in enumerate(rows):
            parts = row.split('\t')
            if len(parts) < 4 or parts[1] != 'Runtime/' + target: continue
            parts[2:4] = [str(len(data)), hashlib.sha256(data).hexdigest()]
            rows[i] = '\t'.join(parts); count += 1
        if count != 1: raise ValueError('expected exactly one FEX artifact row')
        destination = REPO / 'app/Sources/S1Probe/Runtime' / target
        shutil.copyfile(path, destination)
        allowed_outputs.add(str(destination.relative_to(REPO)))
    records.write_text('\n'.join(rows) + '\n')
    shutil.copyfile(records, REPO / 'app/Sources/S1Probe/Runtime/artifacts.tsv')
    after = cp.files(REPO)
    delta = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    if delta - allowed_outputs:
        raise ValueError('unrelated output changed: ' + ', '.join(sorted(delta - allowed_outputs)))
    cp.save(REPO); cp.verify(REPO)
    print('Both FEX modules rebuilt; all other checkpoint bytes retained.')

if __name__ == '__main__': main()
