#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rebuild one i386 kernelbase from the exact bounded diagnostic patch.

All other checkpoint outputs retain their already verified bytes. This is
diagnostic instrumentation, not evidence that any game reaches a first frame.
"""
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import struct
import subprocess

REPO = Path(__file__).resolve().parent.parent
PARENT = '3981c2e3c10b94cb171d5c746f17816ded2b6df6'
PATCH = '0033-kernelbase-record-bounded-i386-compatibility-evidence.patch'
PATCH_SHA = 'a9c3c951889bc77aff886e75672292ffd81482a5a1be8e01a4c277f448b8f136'
ATOM = '0032-wow64-preserve-class-atoms-in-unicode-strings.patch'
ATOM_SHA = '20ecaf174705103508e4b43f1747d0446b19d819db330ebe52455dffb719031d'

def git(*args):
    return subprocess.check_output(['git', '-c', 'core.filemode=false', '-C', str(REPO), *args])

def validate_delta():
    allowed = {'build/rebuild-i386-diagnostics-checkpoint.py', 'patches/wine-pe/series',
               'patches/wine-pe/' + PATCH, 'patches/wine-pe/' + ATOM}
    changed = set(git('diff', '--name-only', PARENT, '--', 'pins.lock', 'patches', 'build',
                      'app/registry', 'app/WindowsNLS', 'app/SessionRoot', 'app/UrlOpener',
                      'app/PlayportJIT', 'app/PlayportJIT-Info.plist').decode().splitlines())
    changed = {p for p in changed if not p.startswith('build/generated/')}
    if changed - allowed:
        raise ValueError('unrelated native inputs: ' + ', '.join(sorted(changed - allowed)))
    if (REPO / 'patches/wine-pe/series').read_bytes() != git('show', PARENT + ':patches/wine-pe/series') + PATCH.encode() + b'\n':
        raise ValueError('not the exact one-patch append')
    for name, digest in [(PATCH, PATCH_SHA), (ATOM, ATOM_SHA)]:
        if hashlib.sha256((REPO / 'patches/wine-pe' / name).read_bytes()).hexdigest() != digest:
            raise ValueError('unexpected patch bytes: ' + name)

def replace_records(output):
    data = output.read_bytes()
    offset = struct.unpack_from('<I', data, 60)[0]
    if data[:2] != b'MZ' or data[offset:offset+4] != b'PE\0\0' or struct.unpack_from('<H', data, offset+4)[0] != 0x14c:
        raise ValueError('not the built i386 kernelbase')
    if b'[win-compat]' not in data:
        raise ValueError('diagnostic code absent from the actual DLL')
    size, digest = str(len(data)), hashlib.sha256(data).hexdigest()
    for name, column, value in [
        ('app/artifacts.tsv', 1, 'Runtime/i386-windows/kernelbase.dll'),
        ('build/generated/wine-pe-i386-windows.tsv', 0, 'dlls/kernelbase/i386-windows/kernelbase.dll')
    ]:
        p = REPO / name
        rows = p.read_text().splitlines(); count = 0
        for i, row in enumerate(rows):
            parts = row.split('\t')
            if len(parts) <= column or parts[column] != value: continue
            parts[column+1:column+3] = [size, digest]
            rows[i] = '\t'.join(parts); count += 1
        if count != 1: raise ValueError('expected exactly one artifact row: ' + name)
        p.write_text('\n'.join(rows) + '\n')
    shutil.copyfile(output, REPO / 'app/Sources/S1Probe/Runtime/i386-windows/kernelbase.dll')
    shutil.copyfile(REPO / 'app/artifacts.tsv', REPO / 'app/Sources/S1Probe/Runtime/artifacts.tsv')

def main():
    validate_delta()
    spec = importlib.util.spec_from_file_location('checkpoint', REPO / 'build/runtime-checkpoint.py')
    cp = importlib.util.module_from_spec(spec); spec.loader.exec_module(cp)
    cp.verify(REPO); before = cp.files(REPO)
    out = REPO / '.work/run/pe'; wine = out / 'wine'
    if not (wine / '.git').exists():
        subprocess.run(['git', 'clone', '--depth=1', '--branch', 'wine-11.19', '--single-branch',
                        'https://github.com/wine-mirror/wine.git', str(wine)], check=True)
    link = out / 'build'
    if not link.exists(): link.symlink_to(REPO / 'upstream/madeira/build', target_is_directory=True)
    env = os.environ.copy(); env.update(OUT=str(out), PLAYPORT_WOW64_ONLY='1')
    # The unchanged recipe applies/checks every patch and configures real tools.
    subprocess.run(['bash', 'build/stages/wine-pe.sh'], cwd=REPO, env=env, check=True)
    subprocess.run(['make', '-j3', 'dlls/kernelbase/i386-windows/kernelbase.dll'], cwd=wine / 'build-macos', check=True)
    output = out / 'kernelbase-i386-diagnostics.dll'
    subprocess.run([str(Path(env['LLVM_MINGW']) / 'bin/llvm-strip'), '--strip-debug', '-o', str(output),
                    str(wine / 'build-macos/dlls/kernelbase/i386-windows/kernelbase.dll')], check=True)
    replace_records(output)
    after = cp.files(REPO)
    allowed = {'app/artifacts.tsv', 'app/Sources/S1Probe/Runtime/artifacts.tsv',
               'build/generated/wine-pe-i386-windows.tsv', 'app/Sources/S1Probe/Runtime/i386-windows/kernelbase.dll'}
    delta = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    if delta - allowed: raise ValueError('unrelated output modified: ' + ', '.join(sorted(delta - allowed)))
    cp.save(REPO); cp.verify(REPO)
    print('Real i386 kernelbase compiled; all other checked outputs retained.')

if __name__ == '__main__': main()
