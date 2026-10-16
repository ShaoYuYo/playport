#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rebuild thread.o with the production recipe; preserve all other members."""
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess

REPO = Path(__file__).resolve().parent.parent
BASE = '970a4afe70d8b2007e4ec0a4fe2274f4eeece82f'
PATCHES = {'0104-ntdll-gate-iOS-self-suspend-before-returning-to-guest.patch': '6f4d5034bdfd0b4f34fba806108fa40f9df58f0b945f6603b6f4372535a0bf9b'}

def git(*args):
    return subprocess.check_output(['git', '-c', 'core.filemode=false', '-C', str(REPO), *args])

def validate():
    paths = ['pins.lock', 'patches', 'build', 'app/registry', 'app/WindowsNLS', 'app/SessionRoot',
             'app/UrlOpener', 'app/PlayportJIT', 'app/PlayportJIT-Info.plist']
    names = set(git('diff', '--name-only', BASE, '--', *paths).decode().splitlines())
    names.update(git('ls-files', '--others', '--exclude-standard', '--', *paths).decode().splitlines())
    allowed = {'patches/madeira-unix/series', 'build/rebuild-self-suspend-checkpoint.py',
               'build/test-self-suspend.py'}
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
    script = root / 'compile-self-suspend.sh'
    script.write_text('set -e\nBUILD_DIR="' + str(build) + '"\nREPO_ROOT="' + str(tree) +
                      '"\nWINE_SRC="$REPO_ROOT/wine"\nWINE_BUILD="$WINE_SRC/build-macos"\n'
                      'SDK=$(xcrun --sdk iphoneos --show-sdk-path)\nOBJ_DIR="$BUILD_DIR/obj"\n'
                      'mkdir -p "$OBJ_DIR"\nSUCCEEDED=0\nFAILED=0\nFAILED_FILES=""\n' + recipe[start:end] +
                      '\ncompile_one "$BUILD_DIR/thread_ios.c" thread\n'
                      'if [ "$FAILED" != 0 ]; then cat "$OBJ_DIR/thread.err"; exit 1; fi\n')
    env['PATH'] = str(root / 'shims') + ':' + env['PATH']
    subprocess.run(['bash', str(script)], env=env, check=True)
    staged = REPO / 'app/Staged/lib/libntdll_unix.a'
    if hashlib.sha256(staged.read_bytes()).hexdigest() != '028d570e4b5246eced39f535aa9250ff828c117bb9db12f8e0672dc378e91a81':
        raise ValueError('expected the r7 verified native checkpoint archive')
    members = subprocess.check_output(['llvm-ar', 't', str(staged)]).decode().splitlines()
    if members.count('thread.o') != 1 or len(members) != len(set(members)):
        raise ValueError('ambiguous archive members')
    old = {m: subprocess.check_output(['llvm-ar', 'p', str(staged), m]) for m in members}
    output = root / 'libntdll-self-suspend.a'; shutil.copyfile(staged, output)
    subprocess.run(['llvm-ar', 'rcsD', str(output), str(build / 'obj/thread.o')], check=True)
    if subprocess.check_output(['llvm-ar', 't', str(output)]).decode().splitlines() != members:
        raise ValueError('archive member order changed')
    for m in members:
        data = subprocess.check_output(['llvm-ar', 'p', str(output), m])
        if m != 'thread.o' and data != old[m]: raise ValueError('unrelated archive member: ' + m)
        if m == 'thread.o' and data == old[m]: raise ValueError('thread.o did not change')
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
    subprocess.run(['python3', 'build/test-self-suspend.py', str(tree)], check=True)
    after = cp.files(REPO)
    allowed = {'app/Staged/lib/libntdll_unix.a', 'app/artifacts.tsv', 'app/Sources/S1Probe/Runtime/artifacts.tsv'}
    changed = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    if changed - allowed: raise ValueError('unrelated checkpoint output changed: ' + ', '.join(sorted(changed - allowed)))
    cp.save(REPO); cp.verify(REPO)
    print('Only thread.o replaced; 34 other native archive members retained. SHA256=' + digest)

if __name__ == '__main__': main()
