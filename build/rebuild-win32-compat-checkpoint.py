#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Migrate the exact complete checkpoint with NLS data and two WoW64 bridge DLLs.

Wine/FEX native archives, renderer, Steam binaries and i386 game DLLs retain
all checked bytes. Only the generic aarch64 WoW64 bridges include the changed
Unicode-string helper. The prior immutable cache is never overwritten.
"""
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import struct
import subprocess

REPO = Path(__file__).resolve().parent.parent
PARENT = '62f9877af5225d7e11d0c6a48edfc26c0f8e37d2'
PATCH_NAME = '0032-wow64-preserve-class-atoms-in-unicode-strings.patch'
SCRIPT_SHA = 'de4448185e97a4d975eece3056f3043a3010c4d910c5b7927cb1baa63b73c11c'
ALLOWED = {'build/rebuild-win32-compat-checkpoint.py', 'build/refresh-nls-checkpoint.py',
           'build/stages/stage-artifacts.py', 'build/stages/wine-pe.sh', 'build/verify-ipa.py',
           'patches/wine-pe/series', 'patches/wine-pe/' + PATCH_NAME,
           'app/WindowsNLS/c_10000.nls', 'app/WindowsNLS/README.md'}

def module(name, file):
    spec = importlib.util.spec_from_file_location(name, REPO / file)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])

def validate_delta():
    if subprocess.run(['git', '-C', str(REPO), 'cat-file', '-e', PARENT + '^{commit}'], capture_output=True).returncode:
        subprocess.run(['git', '-C', str(REPO), 'fetch', '--depth=1', 'origin', PARENT], check=True)
    changed = set(git('diff', '--name-only', PARENT, '--', 'pins.lock', 'patches', 'build',
                      'app/registry', 'app/WindowsNLS', 'app/SessionRoot', 'app/UrlOpener', 'app/PlayportJIT',
                      'app/PlayportJIT-Info.plist').decode().splitlines())
    changed = {p for p in changed if not p.startswith('build/generated/')}
    if changed - ALLOWED:
        raise ValueError('unexpected native input changes: ' + ', '.join(sorted(changed - ALLOWED)))
    if (REPO / 'patches/wine-pe/series').read_text() != git('show', PARENT + ':patches/wine-pe/series').decode() + PATCH_NAME + '\n':
        raise ValueError('Wine PE series is not the one audited header patch append')
    patch = (REPO / 'patches/wine-pe' / PATCH_NAME).read_text()
    if [line for line in patch.splitlines() if line.startswith('diff --git ')] != [
            'diff --git a/dlls/wow64/wow64_private.h b/dlls/wow64/wow64_private.h']:
        raise ValueError('patch changes more than the audited WoW64 header')
    if hashlib.sha256((REPO / 'build/stages/wine-pe.sh').read_bytes()).hexdigest() != SCRIPT_SHA:
        raise ValueError('selective PE recipe is not the reviewed source')
    module('nls', 'build/refresh-nls-checkpoint.py').validate_resource_sources()

def replace_records(repo, outputs):
    manifest = repo / 'app/artifacts.tsv'
    lines = manifest.read_text().splitlines()
    for name, output in outputs.items():
        data = output.read_bytes()
        if len(data) < 256 or data[:2] != b'MZ': raise ValueError('not a real built PE: ' + name)
        offset = struct.unpack_from('<I', data, 60)[0]
        if offset + 24 > len(data) or data[offset:offset+4] != b'PE\0\0' or struct.unpack_from('<H', data, offset+4)[0] != 0xaa64:
            raise ValueError('built bridge is not aarch64 PE: ' + name)
        size, digest = str(len(data)), hashlib.sha256(data).hexdigest()
        matches = [i for i, line in enumerate(lines) if line.split('\t')[1:2] == ['Runtime/aarch64-windows/' + name]]
        if len(matches) != 1: raise ValueError('expected one bridge resource row: ' + name)
        i = matches[0]; row = lines[i].split('\t'); row[2:4] = [size, digest]; lines[i] = '\t'.join(row)
        shutil.copyfile(output, repo / 'app/Sources/S1Probe/Runtime/aarch64-windows' / name)
        generated = repo / 'build/generated/wine-pe-aarch64-windows.tsv'
        records = generated.read_text().splitlines(); count = 0
        for n, record in enumerate(records):
            columns = record.split('\t')
            if columns[0] == 'dlls/' + name[:-4] + '/aarch64-windows/' + name:
                columns[1:3] = [size, digest]; records[n] = '\t'.join(columns); count += 1
        if count != 1: raise ValueError('expected one generated bridge record: ' + name)
        generated.write_text('\n'.join(records) + '\n')
    manifest.write_text('\n'.join(lines) + '\n')
    shutil.copyfile(manifest, repo / 'app/Sources/S1Probe/Runtime/artifacts.tsv')

def main():
    validate_delta()
    checkpoint = module('checkpoint', 'build/runtime-checkpoint.py')
    checkpoint.verify(REPO)
    before = checkpoint.files(REPO)
    out = REPO / '.work/run/pe'; out.mkdir(parents=True, exist_ok=True)
    wine = out / 'wine'
    if not (wine / '.git').exists():
        subprocess.run(['git', 'clone', '--depth=1', '--branch', 'wine-11.19', '--single-branch',
                        'https://github.com/wine-mirror/wine.git', str(wine)], check=True)
    pin = next(line.split()[1] for line in (REPO / 'pins.lock').read_text().splitlines() if line.startswith('wine '))
    if not subprocess.check_output(['git', '-C', str(wine), 'rev-parse', 'HEAD']).decode().strip() == pin:
        raise ValueError('fresh Wine source does not equal pins.lock')
    # The usual PE recipe requires Madeira's own configuration header; no
    # submodule runtime is compiled here and the frozen pin is unchanged.
    subprocess.run(['git', '-C', str(REPO), 'submodule', 'update', '--init', '--depth=1', 'upstream/madeira'], check=True)
    link = out / 'build'
    if not link.exists(): link.symlink_to(REPO / 'upstream/madeira/build', target_is_directory=True)
    env = os.environ.copy(); env.update(OUT=str(out), PLAYPORT_WOW64_ONLY='1')
    subprocess.run(['bash', 'build/stages/wine-pe.sh'], cwd=REPO, env=env, check=True)
    mingw = Path(env['LLVM_MINGW'])
    outputs = {}
    for name in ('wow64.dll', 'wow64win.dll'):
        built = wine / 'build-macos/dlls' / name[:-4] / 'aarch64-windows' / name
        stripped = out / name
        subprocess.run([str(mingw / 'bin/llvm-strip'), '--strip-debug', '-o', str(stripped), str(built)], check=True)
        subprocess.run([str(mingw / 'bin/llvm-readobj'), '--file-headers', '--coff-exports', str(stripped)], check=True)
        outputs[name] = stripped
    replace_records(REPO, outputs)
    module('nls', 'build/refresh-nls-checkpoint.py').refresh(REPO)
    after = checkpoint.files(REPO)
    allowed = {'app/artifacts.tsv', 'app/Sources/S1Probe/Runtime/artifacts.tsv',
               'build/generated/wine-pe-aarch64-windows.tsv',
               'app/Sources/S1Probe/Runtime/nls/c_10000.nls',
               'app/Sources/S1Probe/Runtime/aarch64-windows/wow64.dll',
               'app/Sources/S1Probe/Runtime/aarch64-windows/wow64win.dll'}
    delta = {path for path in before.keys() | after.keys() if before.get(path) != after.get(path)}
    if delta - allowed: raise ValueError('unrelated cached binary was modified: ' + ', '.join(sorted(delta - allowed)))
    checkpoint.save(REPO); checkpoint.verify(REPO)
    print('Verified compatibility migration: two real WoW64 DLLs + pinned NLS table; all other checked outputs retained.')

if __name__ == '__main__': main()
