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
BASE = 'e209421aba0f4dc9bbae1746901423d9783e2264'
PATCH = '0101-WoW64-preserve-adjacent-data-on-guest-subpage-decommit.patch'

def git(*args):
    return subprocess.check_output(['git', '-c', 'core.filemode=false', '-C', str(REPO), *args])

def validate():
    paths = ['pins.lock', 'patches', 'build', 'app/registry', 'app/WindowsNLS', 'app/SessionRoot',
             'app/UrlOpener', 'app/PlayportJIT', 'app/PlayportJIT-Info.plist']
    names = set(git('diff', '--name-only', BASE, '--', *paths).decode().splitlines())
    names.update(git('ls-files', '--others', '--exclude-standard', '--', *paths).decode().splitlines())
    allowed = {'patches/madeira-unix/series', 'patches/madeira-unix/' + PATCH,
               'build/rebuild-wow64-subpage-checkpoint.py', 'build/wow64/test.py',
               'build/wow64/vm_test.c', 'build/wow64/subpage_test.c'}
    for name in names:
        if name.startswith('build/generated/'): continue
        old = subprocess.run(['git', '-C', str(REPO), 'show', BASE + ':' + name], capture_output=True)
        actual = (REPO / name).read_bytes() if (REPO / name).is_file() else None
        if (old.returncode or old.stdout != actual) and name not in allowed:
            raise ValueError('unrelated native input: ' + name)
    if (REPO / 'patches/madeira-unix/series').read_bytes() != git('show', BASE + ':patches/madeira-unix/series') + PATCH.encode() + b'\n':
        raise ValueError('expected the exact subpage patch append')
    if hashlib.sha256((REPO / 'patches/madeira-unix' / PATCH).read_bytes()).hexdigest() != 'aab89cf7623ec5a747c591b0c86ce55786fa4cddaaa78b1423b870e9284c5a17':
        raise ValueError('unexpected subpage patch bytes')

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
    if hashlib.sha256(staged.read_bytes()).hexdigest() not in {'62d800dc7e2c689ce3d25376222d59338d2d9f64b4d7f0446916400e96442ce6',
                 '5eae3704da1ae41c0d63ed200de11a63612d16e9a8bd1bd598cc9526418bd417'}:
        raise ValueError('expected the verified native checkpoint archive')
    members = subprocess.check_output(['llvm-ar', 't', str(staged)]).decode().splitlines()
    if members.count('virtual.o') != 1 or len(members) != len(set(members)):
        raise ValueError('ambiguous archive members')
    old = {m: subprocess.check_output(['llvm-ar', 'p', str(staged), m]) for m in members}
    output = root / 'libntdll-subpage.a'; shutil.copyfile(staged, output)
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
