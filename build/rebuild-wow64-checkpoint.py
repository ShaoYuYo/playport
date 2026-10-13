#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Migrate the known native checkpoint by rebuilding only Wine's virtual.o.

Fail closed on unrelated native changes. Every cached byte is checked before
replacement, the existing archive must contain exactly one virtual.o, and the
replacement uses the patched upstream build script's actual compile function.
The original immutable Actions cache remains available if this build fails.
"""
import hashlib
import importlib.util
from pathlib import Path
import shutil
import subprocess

REPO = Path(__file__).resolve().parent.parent
PARENT = '750a37f124ab08ea2f2673d0553184fae6810aae'
PATCH_NAME = '0099-ntdll-reserve-title-WoW64-window-before-FEX.patch'
PATCH = 'patches/madeira-unix/' + PATCH_NAME
ALLOWED = {PATCH, 'patches/madeira-unix/series', 'build/rebuild-wow64-checkpoint.py',
           'build/wow64/preflight_test.c'}

def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])

def validate_delta():
    changed = set(git('diff', '--name-only', PARENT, '--', 'pins.lock', 'patches', 'build',
                      'app/registry', 'app/SessionRoot', 'app/UrlOpener', 'app/PlayportJIT',
                      'app/PlayportJIT-Info.plist').decode().splitlines())
    changed = {p for p in changed if not p.startswith('build/generated/')}
    if changed - ALLOWED:
        raise ValueError('unrelated native input changes: ' + ', '.join(sorted(changed - ALLOWED)))
    before = git('show', PARENT + ':patches/madeira-unix/series').decode()
    if (REPO / 'patches/madeira-unix/series').read_text() != before + PATCH_NAME + '\n':
        raise ValueError('native patch series is not the expected one-patch append')
    text = (REPO / PATCH).read_text()
    paths = [line for line in text.splitlines() if line.startswith('diff --git ')]
    if paths != ['diff --git a/build/ntdll-unix/virtual_ios.c b/build/ntdll-unix/virtual_ios.c']:
        raise ValueError('migration patch changes a native object besides virtual.o')

def refresh_record(archive):
    manifest = REPO / 'app/artifacts.tsv'
    lines = manifest.read_text().splitlines()
    updated = 0
    for i, line in enumerate(lines):
        row = line.split('\t')
        if len(row) == 7 and row[:2] == ['link', 'lib/libntdll_unix.a']:
            row[2:4] = [str(archive.stat().st_size), hashlib.sha256(archive.read_bytes()).hexdigest()]
            lines[i] = '\t'.join(row)
            updated += 1
    if updated != 1:
        raise ValueError('expected one libntdll_unix.a artifact record')
    manifest.write_text('\n'.join(lines) + '\n')
    shutil.copyfile(manifest, REPO / 'app/Sources/S1Probe/Runtime/artifacts.tsv')

def main():
    if subprocess.run(['git', '-C', str(REPO), 'cat-file', '-e', PARENT], capture_output=True).returncode:
        subprocess.run(['git', '-C', str(REPO), 'fetch', '--no-recurse-submodules', 'origin', PARENT], check=True)
    validate_delta()
    subprocess.run(['python3', 'build/runtime-checkpoint.py', 'verify'], cwd=REPO, check=True)
    root = REPO / '.work/run/unix'
    # Only prepare source/header inputs. GnuTLS, FEX, Wine PE, DXMT, Mesa and
    # Steam binaries in the verified checkpoint remain byte-for-byte retained.
    subprocess.run(['bash', 'build/stages/unix.sh', str(root), 'clones', 'shims', 'configure', 'widl'],
                   cwd=REPO, check=True)
    config = root / 'wine/build-macos/include/config.h'
    with config.open('a') as f:
        f.write('\n#define HAVE_GNUTLS_CIPHER_INIT 1\n#define SONAME_LIBGNUTLS "libgnutls.30.dylib"\n')
    build = root / 'mythic/build/ntdll-unix'
    original = (build / 'build.sh').read_text()
    # Execute the same compile_one implementation, shims and flags as a full
    # build; do not duplicate or quietly change the compiler contract.
    preamble = original[:original.index('echo "=== Building ntdll unix (iOS) ==="')]
    script = build / 'virtual-only.sh'
    script.write_text(preamble + '\ncompile_one "$BUILD_DIR/virtual_ios.c" "virtual"\n'
                      'test "$SUCCEEDED" = 1 && test "$FAILED" = 0\n')
    env = __import__('os').environ.copy()
    env['PATH'] = str(root / 'shims') + ':' + env['PATH']
    subprocess.run(['bash', str(script)], env=env, cwd=REPO, check=True)
    archive = REPO / 'app/Staged/lib/libntdll_unix.a'
    members = subprocess.check_output(['llvm-ar', 't', str(archive)]).decode().splitlines()
    if members.count('virtual.o') != 1:
        raise ValueError('cached ntdll archive does not contain exactly one virtual.o')
    obj = build / 'obj/virtual.o'
    subprocess.run(['llvm-ar', 'r', str(archive), str(obj)], check=True)
    subprocess.run(['llvm-ranlib', str(archive)], check=True)
    symbols = subprocess.check_output(['llvm-nm', '--defined-only', str(archive)]).decode()
    if '_ios_set_title_machine' not in symbols:
        raise ValueError('new title allocation ABI missing from ntdll')
    refresh_record(archive)
    subprocess.run(['python3', 'build/runtime-checkpoint.py', 'save'], cwd=REPO, check=True)
    subprocess.run(['python3', 'build/runtime-checkpoint.py', 'verify'], cwd=REPO, check=True)
    print('Verified checkpoint migrated: only libntdll_unix.a virtual.o rebuilt; all other native outputs retained.')

if __name__ == '__main__':
    main()
