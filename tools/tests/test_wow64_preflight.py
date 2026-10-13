# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile the actual native patch's early window functions and PE reader."""
from pathlib import Path
import importlib.util
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
PATCH = REPO / 'patches/madeira-unix/0099-ntdll-reserve-title-WoW64-window-before-FEX.patch'
spec = importlib.util.spec_from_file_location('wow64_tests', REPO / 'build/wow64/test.py')
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)

class WoW64Preflight(unittest.TestCase):
    def test_production_reservation_functions(self):
        scratch = REPO / '.work/c-test'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as t:
            root = Path(t)
            text = PATCH.read_text()
            setter = text[text.index('+void ios_set_title_machine'):text.index('+/* Reserve the complete')]
            setter = '\n'.join(l[1:] for l in setter.splitlines() if l.startswith('+'))
            (root / 'preflight_api.h').write_text(setter + '\n' + ''.join(
                helpers.patched_function(PATCH, declaration) for declaration in (
                    'static NTSTATUS ios_wow64_prepare_title_window(void)',
                    'static NTSTATUS ios_wow64_take_title_window( struct file_view **view )')))
            exe = root / 'test'
            subprocess.run([shutil.which('clang') or 'gcc', '-D_POSIX_C_SOURCE=200809L',
                            '-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=undefined',
                            '-fno-sanitize-recover=all', '-I', str(root),
                            str(REPO / 'build/wow64/preflight_test.c'), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)

    def test_coff_machine_from_actual_file(self):
        import ctypes
        scratch = REPO / '.work/c-test'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as t:
            root = Path(t)
            lib = root / 'reader.so'
            subprocess.run([shutil.which('clang') or 'gcc', '-shared', '-fPIC', '-Wall', '-Wextra', '-Werror',
                            '-I', str(REPO / 'app/Sources/WineHost/include'),
                            str(REPO / 'app/Sources/WineHost/title_path.c'), '-o', str(lib)], check=True)
            read = ctypes.CDLL(str(lib)).title_path_machine
            read.argtypes = [ctypes.c_char_p]
            read.restype = ctypes.c_ushort
            p = root / 'game.exe'
            def check(data, want):
                p.write_bytes(data)
                self.assertEqual(read(str(p).encode()), want)
            dos = bytearray(128); dos[:2] = b'MZ'; dos[60:64] = (128).to_bytes(4, 'little')
            for machine in (0x14c, 0x8664, 0xaa64):
                check(dos + b'PE\0\0' + machine.to_bytes(2, 'little'), machine)
            check(b'', 0)
            check(b'MZ', 0)
            check(dos + b'NE\0\0\x4c\x01', 0)
            check(dos + b'PE\0\0\x4c', 0)
            dos[60:64] = (0xffffffff).to_bytes(4, 'little')
            check(dos, 0)
            self.assertEqual(read(None), 0)
            p.unlink()
            self.assertEqual(read(str(p).encode()), 0)
