# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib
import importlib.util
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('nls_refresh', REPO / 'build/refresh-nls-checkpoint.py')
refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh)

def function(text, name):
    start = text.index('static int ' + name + '(')
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += {'{': 1, '}': -1}.get(text[end], 0)
        end += 1
    return text[start:end]

class WindowsNLS(unittest.TestCase):
    def test_real_table_and_idempotent_checkpoint_refresh(self):
        data = (REPO / 'app/WindowsNLS/c_10000.nls').read_bytes()
        self.assertEqual((len(data), hashlib.sha256(data).hexdigest()), (refresh.SIZE, refresh.SHA256))
        self.assertEqual(struct.unpack_from('<3H', data), (13, 10000, 1))
        table = struct.unpack('<' + str(len(data) // 2) + 'H', data)
        self.assertEqual(table[14 + 0x41], 0x41)
        self.assertEqual(table[14 + 0x80], 0x00c4)  # actual Mac Roman Ä
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            (repo / 'app/WindowsNLS').mkdir(parents=True)
            (repo / 'app/WindowsNLS/c_10000.nls').write_bytes(data)
            (repo / 'app/artifacts.tsv').write_text('# record\n')
            refresh.refresh(repo)
            first = (repo / 'app/artifacts.tsv').read_bytes()
            refresh.refresh(repo)
            self.assertEqual((repo / 'app/artifacts.tsv').read_bytes(), first)
            self.assertEqual((repo / 'app/Sources/S1Probe/Runtime/nls/c_10000.nls').read_bytes(), data)
            (repo / 'app/WindowsNLS/c_10000.nls').write_bytes(data[:-1])
            with self.assertRaises(ValueError): refresh.refresh(repo)

    def test_actual_host_links_windows_nls_farms_without_touching_game_data(self):
        source = (REPO / 'app/Sources/WineHost/wine_host.c').read_text()
        code = '''#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
static char g_runtime[1000], g_prefix[1000];
static void host_log(const char *format, ...) { (void)format; }
'''
        code += function(source, 'mkdirs') + '\n' + function(source, 'link_dir_into') + '\n' + function(source, 'link_nls_dirs')
        code += '''
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    snprintf(g_prefix, sizeof(g_prefix), "%s", argv[1]);
    snprintf(g_runtime, sizeof(g_runtime), "%s", argv[2]);
    return link_nls_dirs() == 0 ? 0 : 1;
}
'''
        scratch = REPO / '.work/tests'; scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            root = Path(tmp); c = root / 'test.c'; c.write_text(code); exe = root / 'test'
            subprocess.run(['cc', '-Wall', '-Werror', str(c), '-o', str(exe)], check=True)
            prefix = root / 'prefix'; game = prefix / 'drive_c/Games/test/save'; game.mkdir(parents=True)
            saved = game / 'keep.dat'; saved.write_bytes(b'save')
            for bundle in ('first', 'upgrade'):
                nls = root / bundle / 'nls'; nls.mkdir(parents=True)
                (nls / 'c_10000.nls').write_bytes(b'nls')
                (nls / 'c_932.nls').write_bytes(b'cp932')
                subprocess.run([str(exe), str(prefix), str(nls.parent)], check=True)
                for directory in ('system32', 'syswow64', 'sysarm64'):
                    target = prefix / 'drive_c/windows' / directory / 'c_10000.nls'
                    self.assertTrue(target.is_symlink())
                    self.assertEqual(target.resolve(), (nls / 'c_10000.nls').resolve())
                self.assertEqual(saved.read_bytes(), b'save')
            self.assertNotEqual(subprocess.run([str(exe), str(prefix), str(root / 'missing')]).returncode, 0)

if __name__ == '__main__': unittest.main()
