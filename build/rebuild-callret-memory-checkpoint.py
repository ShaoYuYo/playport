#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rebuild virtual.o for the reviewed diagnostic geometry; preserve other members."""
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess

REPO = Path(__file__).resolve().parent.parent
BASE = 'a1504b9de0774510b05e7bea6058ca4efbcaac1c'
PATCHES = {'0105-ntdll-report-compact-FEX-span-and-callret-geometry.patch': 'a34959c00fd3c06d2a429b473ade52f5d935a8130ebd255078b370d7839d05bc'}
FEX_PATCH = '0027-iOS-trim-callret-reservations-and-bound-callback-pushes.patch'
FEX_SHA = '4ed54fe98af64cb5e01b532095405e2fa41902e5409f6fd0659308f675efb286'

def git(*args):
    return subprocess.check_output(['git', '-c', 'core.filemode=false', '-C', str(REPO), *args])

def validate():
    paths = ['pins.lock', 'patches', 'build', 'app/registry', 'app/WindowsNLS', 'app/SessionRoot',
             'app/UrlOpener', 'app/PlayportJIT', 'app/PlayportJIT-Info.plist']
    names = set(git('diff', '--name-only', BASE, '--', *paths).decode().splitlines())
    names.update(git('ls-files', '--others', '--exclude-standard', '--', *paths).decode().splitlines())
    allowed = {'patches/madeira-unix/series','patches/fex/series','patches/fex/'+FEX_PATCH,
               'build/rebuild-callret-memory-checkpoint.py','build/rebuild-callret-memory-fex.py',
               'build/test-callret-reservation.py','build/test-arena-census.py','build/test-wow64-callret.py'}
    allowed.update('patches/madeira-unix/' + p for p in PATCHES)
    for name in names:
        if name.startswith('build/generated/'): continue
        old = subprocess.run(['git', '-C', str(REPO), 'show', BASE + ':' + name], capture_output=True)
        actual = (REPO / name).read_bytes() if (REPO / name).is_file() else None
        if (old.returncode or old.stdout != actual) and name not in allowed:
            raise ValueError('unrelated native input: ' + name)
    if (REPO / 'patches/madeira-unix/series').read_bytes() != git('show', BASE + ':patches/madeira-unix/series') + ''.join(p + '\n' for p in PATCHES).encode():
        raise ValueError('expected the exact reviewed patch append')
    for name, digest in PATCHES.items():
        if hashlib.sha256((REPO / 'patches/madeira-unix' / name).read_bytes()).hexdigest() != digest:
            raise ValueError('unexpected patch bytes: ' + name)
    if (REPO/'patches/fex/series').read_bytes()!=git('show',BASE+':patches/fex/series')+FEX_PATCH.encode()+b'\n':raise ValueError('unexpected FEX patch append')
    if hashlib.sha256((REPO/'patches/fex'/FEX_PATCH).read_bytes()).hexdigest()!=FEX_SHA:raise ValueError('unexpected FEX patch')

def main():
    validate()
    spec = importlib.util.spec_from_file_location('cp', REPO / 'build/runtime-checkpoint.py')
    cp = importlib.util.module_from_spec(spec); spec.loader.exec_module(cp)
    cp.verify(REPO); before = cp.files(REPO)
    root = REPO / '.work/run/unix'; tree = root / 'mythic'
    env = os.environ.copy()
    local_wine = REPO / '.work/run/pe/wine'
    if (local_wine / '.git').exists(): env['SRC_WINE'] = str(local_wine)
    subprocess.run(['bash', 'build/stages/unix.sh', str(root), 'clones', 'shims'], env=env, check=True)
    if not (root / 'wine/build-macos/include/config.h').exists():
        subprocess.run(['bash', 'build/stages/unix.sh', str(root), 'configure', 'widl'], env=env, check=True)
    build = tree / 'build/ntdll-unix'
    recipe = (build / 'build.sh').read_text()
    start = recipe.index('compile_one() {'); end = recipe.index('\n}\n', start) + 3
    script = root / 'compile-callret-census.sh'
    script.write_text('set -e\nBUILD_DIR="' + str(build) + '"\nREPO_ROOT="' + str(tree) +
                      '"\nWINE_SRC="$REPO_ROOT/wine"\nWINE_BUILD="$WINE_SRC/build-macos"\n'
                      'SDK=$(xcrun --sdk iphoneos --show-sdk-path)\nOBJ_DIR="$BUILD_DIR/obj"\n'
                      'mkdir -p "$OBJ_DIR"\nSUCCEEDED=0\nFAILED=0\nFAILED_FILES=""\n' + recipe[start:end] +
                      '\ncompile_one "$BUILD_DIR/virtual_ios.c" virtual\n'
                      'if [ "$FAILED" != 0 ]; then cat "$OBJ_DIR/virtual.err"; exit 1; fi\n')
    env['PATH'] = str(root / 'shims') + ':' + env['PATH']
    subprocess.run(['bash', str(script)], env=env, check=True)
    staged = REPO / 'app/Staged/lib/libntdll_unix.a'
    if hashlib.sha256(staged.read_bytes()).hexdigest() != 'a606eb427546f0771946b1db8ea544c2fd30f730a33d87a4dcdc75af9a31caff':
        raise ValueError('expected the verified pre-census native archive')
    members = subprocess.check_output(['llvm-ar', 't', str(staged)]).decode().splitlines()
    if members.count('virtual.o') != 1 or len(members) != len(set(members)):
        raise ValueError('ambiguous archive members')
    old = {m: subprocess.check_output(['llvm-ar', 'p', str(staged), m]) for m in members}
    output = root / 'libntdll-callret-census.a'; shutil.copyfile(staged, output)
    subprocess.run(['llvm-ar', 'rcsD', str(output), str(build / 'obj/virtual.o')], check=True)
    if subprocess.check_output(['llvm-ar', 't', str(output)]).decode().splitlines() != members:
        raise ValueError('archive member order changed')
    for m in members:
        data = subprocess.check_output(['llvm-ar', 'p', str(output), m])
        if m != 'virtual.o' and data != old[m]: raise ValueError('unrelated archive member: ' + m)
        if m == 'virtual.o' and data == old[m]: raise ValueError('virtual.o did not change')
    data = output.read_bytes(); size = str(len(data)); digest = hashlib.sha256(data).hexdigest()
    records = REPO / 'app/artifacts.tsv'; rows = records.read_text().splitlines(); count = 0
    for i, row in enumerate(rows):
        parts = row.split('\t')
        if len(parts) < 4 or parts[1] != 'lib/libntdll_unix.a': continue
        parts[2:4] = [size, digest]; rows[i] = '\t'.join(parts); count += 1
    if count != 1: raise ValueError('expected one ntdll artifact row')
    records.write_text('\n'.join(rows) + '\n')
    shutil.copyfile(records, REPO / 'app/Sources/S1Probe/Runtime/artifacts.tsv')
    shutil.copyfile(output, staged)
    destination = tree / 'app/Madeira/libntdll_unix.a'; destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(output, destination)
    subprocess.run(['python3', 'build/test-arena-census.py', str(tree)], check=True)
    after = cp.files(REPO)
    allowed = {'app/Staged/lib/libntdll_unix.a', 'app/artifacts.tsv', 'app/Sources/S1Probe/Runtime/artifacts.tsv'}
    changed = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    if changed - allowed: raise ValueError('unrelated checkpoint output changed: ' + ', '.join(sorted(changed - allowed)))
    cp.save(REPO); cp.verify(REPO)
    print('Only virtual.o replaced; 34 other native archive members retained. SHA256=' + digest)

if __name__ == '__main__': main()
