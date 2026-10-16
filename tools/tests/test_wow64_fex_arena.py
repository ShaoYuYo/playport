# SPDX-License-Identifier: GPL-3.0-or-later
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
REPO = Path(__file__).resolve().parents[2]
PATCH = REPO / 'patches/madeira-unix/0100-ntdll-seed-WoW64-FEX-arena-before-JIT-copy.patch'
spec = importlib.util.spec_from_file_location('wow_helpers', REPO / 'build/wow64/test.py')
helpers = importlib.util.module_from_spec(spec); spec.loader.exec_module(helpers)
class Arena(unittest.TestCase):
    def test_production_parser_and_handoff_before_first_crt_allocation(self):
        scratch = REPO / '.work/c-test'; scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as t:
            root = Path(t)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            subprocess.run(['git', '-C', str(root), 'apply', '--include=build/ntdll-unix/wow64_fex_arena.h', str(PATCH)], check=True)
            capacity = REPO / 'patches/madeira-unix/0102-ntdll-fit-WoW64-host-arenas-into-sub-gigabyte-gaps.patch'
            subprocess.run(['git', '-C', str(root), 'apply', '--include=build/ntdll-unix/wow64_fex_arena.h', str(capacity)], check=True)
            (root / 'seed_api.h').write_text(helpers.patched_function(PATCH,
                'static int ios_wow64_seed_fex_arena(void *image, size_t size)'))
            exe = root / 'test'
            subprocess.run([shutil.which('clang') or 'gcc', '-D_POSIX_C_SOURCE=200809L', '-std=c11', '-O1',
                            '-Wall', '-Wextra', '-Werror', '-fsanitize=undefined', '-fno-sanitize-recover=all',
                            '-I', str(root), '-I', str(root / 'build/ntdll-unix'),
                            str(REPO / 'build/wow64/fex_arena_test.c'), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)
