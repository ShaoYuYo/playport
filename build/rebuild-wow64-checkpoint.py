#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Migrate the known native checkpoint by rebuilding Wine virtual.o and WoW64 FEX DATA exports.

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
PARENT = '63f8f3fff4257bd483e1b999c95641d494dafbfe'
PATCH_NAME = '0100-ntdll-seed-WoW64-FEX-arena-before-JIT-copy.patch'
PATCH = 'patches/madeira-unix/' + PATCH_NAME
FEX_PATCH_NAME = '0023-WOW64-expose-arena-data-for-pre-CRT-handoff.patch'
FEX_PATCH = 'patches/fex/' + FEX_PATCH_NAME
ALLOWED = {PATCH, 'patches/madeira-unix/series', FEX_PATCH, 'patches/fex/series',
           'build/rebuild-wow64-checkpoint.py', 'build/wow64/fex_arena_test.c',
           'build/stages/fex.sh', 'build/verify-ipa.py'}

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
    if paths != ['diff --git a/build/ntdll-unix/virtual_ios.c b/build/ntdll-unix/virtual_ios.c',
                 'diff --git a/build/ntdll-unix/wow64_fex_arena.h b/build/ntdll-unix/wow64_fex_arena.h']:
        raise ValueError('migration patch changes a native object besides virtual.o')
    before_fex = git('show', PARENT + ':patches/fex/series').decode()
    if (REPO / 'patches/fex/series').read_text() != before_fex + FEX_PATCH_NAME + '\n':
        raise ValueError('unexpected FEX patch series change')
    paths = [l for l in (REPO / FEX_PATCH).read_text().splitlines() if l.startswith('diff --git ')]
    if paths != ['diff --git a/Source/Windows/WOW64/libwow64fex.def b/Source/Windows/WOW64/libwow64fex.def']:
        raise ValueError('FEX migration must change only the WoW64 DATA exports')

def refresh_record(archive, dll=None):
    manifest = REPO / 'app/artifacts.tsv'
    lines = manifest.read_text().splitlines()
    updated = 0
    targets = {'lib/libntdll_unix.a': archive}
    if dll is not None: targets['Runtime/aarch64-windows/xtajit.dll'] = dll
    for i, line in enumerate(lines):
        row = line.split('\t')
        if len(row) == 7 and row[1] in targets:
            output = targets[row[1]]
            row[2:4] = [str(output.stat().st_size), hashlib.sha256(output.read_bytes()).hexdigest()]
            lines[i] = '\t'.join(row)
            updated += 1
    if updated != len(targets):
        raise ValueError('expected one artifact record for each migrated output')
    manifest.write_text('\n'.join(lines) + '\n')
    shutil.copyfile(manifest, REPO / 'app/Sources/S1Probe/Runtime/artifacts.tsv')

def validate_fex_data_exports(dll, header):
    """Run the native parser over the newly built DLL's real mapped image."""
    import ctypes
    import struct
    data = dll.read_bytes()
    po = struct.unpack_from('<I', data, 60)[0]
    ns, osize = struct.unpack_from('<H', data, po + 6)[0], struct.unpack_from('<H', data, po + 20)[0]
    image_size = struct.unpack_from('<I', data, po + 24 + 56)[0]
    header_size = struct.unpack_from('<I', data, po + 24 + 60)[0]
    if image_size > 64 * 1024 * 1024 or header_size > len(data):
        raise ValueError('invalid built FEX image size')
    mapped = bytearray(image_size)
    mapped[:header_size] = data[:header_size]
    for i in range(ns):
        off = po + 24 + osize + i * 40
        va, raw_size, raw_off = struct.unpack_from('<III', data, off + 12)
        if va + raw_size > image_size or raw_off + raw_size > len(data):
            raise ValueError('built FEX section is outside its image/file')
        mapped[va:va + raw_size] = data[raw_off:raw_off + raw_size]
    source = REPO / '.work/run/fex-data-validator.c'
    library = source.with_suffix('.so')
    source.write_text('#include "wow64_fex_arena.h"\nint validate(const void *p, size_t n, uint32_t *out) { return ios_wow64_fex_arena_slots(p, n, out); }\n')
    subprocess.run(['gcc', '-shared', '-fPIC', '-O2', '-I', str(header.parent), str(source), '-o', str(library)], check=True)
    validate = ctypes.CDLL(str(library)).validate
    validate.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_uint32)]
    buffer = ctypes.create_string_buffer(bytes(mapped))
    slots = (ctypes.c_uint32 * 2)()
    if not validate(buffer, image_size, slots):
        subprocess.run([str(Path(__import__('os').environ['LLVM_MINGW']) / 'bin/llvm-readobj'), '--sections', '--coff-exports', str(dll)], check=True)
        raise ValueError('actual WoW64 FEX DATA exports rejected by native handoff parser')
    print(f'Actual WoW64 FEX DATA slots verified before shipping: base RVA={slots[0]:#x}, end RVA={slots[1]:#x}')

def main():
    if subprocess.run(['git', '-C', str(REPO), 'cat-file', '-e', PARENT], capture_output=True).returncode:
        subprocess.run(['git', '-C', str(REPO), 'fetch', '--no-recurse-submodules', 'origin', PARENT], check=True)
    validate_delta()
    subprocess.run(['python3', 'build/runtime-checkpoint.py', 'verify'], cwd=REPO, check=True)
    root = REPO / '.work/run/unix'
    # Prepare native source/header inputs. GnuTLS, ARM64EC FEX, Wine PE,
    # DXMT, Mesa and Steam binaries remain byte-for-byte retained.
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
    result = subprocess.run(['bash', str(script)], env=env, cwd=REPO)
    if result.returncode:
        print((build / 'obj/virtual.err').read_text(), flush=True)
        result.check_returncode()
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
    # Rebuild only the WoW64 FEX DLL: its export directory gained two DATA
    # channels; ARM64EC FEX, Wine PE, DXMT and Mesa are unchanged.
    subprocess.run(['bash', 'build/stages/fex.sh', str(REPO / '.work/run'), 'wow64'], cwd=REPO, check=True)
    dll = REPO / 'app/Sources/S1Probe/Runtime/aarch64-windows/xtajit.dll'
    built_dll = REPO / '.work/run/fex/build-wow64/Bin/libwow64fex.dll'
    validate_fex_data_exports(built_dll, build / 'wow64_fex_arena.h')
    shutil.copyfile(built_dll, dll)
    refresh_record(archive, dll)
    subprocess.run(['python3', 'build/runtime-checkpoint.py', 'save'], cwd=REPO, check=True)
    subprocess.run(['python3', 'build/runtime-checkpoint.py', 'verify'], cwd=REPO, check=True)
    print('Verified checkpoint migrated: virtual.o and WoW64 FEX DATA exports rebuilt; all other native outputs retained.')

if __name__ == '__main__':
    main()
