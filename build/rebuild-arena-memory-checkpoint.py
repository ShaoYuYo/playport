#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rebuild virtual.o with the production recipe; preserve all other members."""
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess

REPO = Path(__file__).resolve().parent.parent
BASE = 'b27332c43c0400f0e93c77fc4717306b69ec2315'
PATCHES = {'0102-ntdll-fit-WoW64-host-arenas-into-sub-gigabyte-gaps.patch': '3c46e70cfb6ca4d740e6911e1ceb93a9030a9929a15a434f51bffeff56471df9', '0103-ntdll-check-new-commitments-against-RAM-headroom.patch': 'a9c3d9e793d2042fd13535ae70442a7ee276631ba042603ed7b07973c2c14001'}

def git(*args):
    return subprocess.check_output(['git', '-c', 'core.filemode=false', '-C', str(REPO), *args])

def validate():
    paths = ['pins.lock', 'patches', 'build', 'app/registry', 'app/WindowsNLS', 'app/SessionRoot',
             'app/UrlOpener', 'app/PlayportJIT', 'app/PlayportJIT-Info.plist']
    names = set(git('diff', '--name-only', BASE, '--', *paths).decode().splitlines())
    names.update(git('ls-files', '--others', '--exclude-standard', '--', *paths).decode().splitlines())
    allowed = {'patches/madeira-unix/series', 'build/rebuild-arena-memory-checkpoint.py',
               'build/test-fex-arena-capacity.py', 'build/test-memory-safety.py',
               'build/wow64/test.py', 'build/wow64/fex_arena_test.c'}
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
    script = root / 'compile-subpage.sh'
    script.write_text('set -e\nBUILD_DIR="' + str(build) + '"\nREPO_ROOT="' + str(tree) +
                      '"\nWINE_SRC="$REPO_ROOT/wine"\nWINE_BUILD="$WINE_SRC/build-macos"\n'
                      'SDK=$(xcrun --sdk iphoneos --show-sdk-path)\nOBJ_DIR="$BUILD_DIR/obj"\n'
                      'mkdir -p "$OBJ_DIR"\nSUCCEEDED=0\nFAILED=0\nFAILED_FILES=""\n' + recipe[start:end] +
                      '\ncompile_one "$BUILD_DIR/virtual_ios.c" virtual\n'
                      'if [ "$FAILED" != 0 ]; then cat "$OBJ_DIR/virtual.err"; exit 1; fi\n')
    env['PATH'] = str(root / 'shims') + ':' + env['PATH']
    subprocess.run(['bash', str(script)], env=env, check=True)
    staged = REPO / 'app/Staged/lib/libntdll_unix.a'
    if hashlib.sha256(staged.read_bytes()).hexdigest() not in {'d977b7a974b23cf40ec1728eab25592a4a0ca66f20e56f8051a2b2484db10cb8',
                 '687ac289469c495183a2a79a723a899c02a0c4c6ee560f5e6088c97c34285987'}:
        raise ValueError('expected the verified native checkpoint archive')
    members = subprocess.check_output(['llvm-ar', 't', str(staged)]).decode().splitlines()
    if members.count('virtual.o') != 1 or len(members) != len(set(members)):
        raise ValueError('ambiguous archive members')
    old = {m: subprocess.check_output(['llvm-ar', 'p', str(staged), m]) for m in members}
    output = root / 'libntdll-arena-memory.a'; shutil.copyfile(staged, output)
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
    after = cp.files(REPO)
    allowed = {'app/Staged/lib/libntdll_unix.a', 'app/artifacts.tsv', 'app/Sources/S1Probe/Runtime/artifacts.tsv'}
    changed = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    if changed - allowed: raise ValueError('unrelated checkpoint output changed: ' + ', '.join(sorted(changed - allowed)))
    cp.save(REPO); cp.verify(REPO)
    print('Only virtual.o replaced; 34 other native archive members retained. SHA256=' + digest)

if __name__ == '__main__': main()
