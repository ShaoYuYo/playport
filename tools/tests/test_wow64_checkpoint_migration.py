# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('migration', REPO / 'build/rebuild-wow64-checkpoint.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class Migration(unittest.TestCase):
    def test_rejects_unrelated_native_changes_and_wrong_patch_scope(self):
        with patch.object(m, 'git', return_value=b'pins.lock\n'):
            with self.assertRaisesRegex(ValueError, 'unrelated native'):
                m.validate_delta()
        before = (REPO / 'patches/madeira-unix/series').read_text().removesuffix(m.PATCH_NAME + '\n')
        def response(*args):
            return b'patches/madeira-unix/series\n' if args[0] == 'diff' else before.encode()
        with patch.object(m, 'git', side_effect=response):
            m.validate_delta()

    def test_manifest_refresh_keeps_other_records(self):
        scratch = REPO / '.work/tmp'; scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as t:
            root = Path(t)
            (root / 'app/Sources/S1Probe/Runtime').mkdir(parents=True)
            archive = root / 'new.a'; archive.write_bytes(b'new virtual object in old archive')
            manifest = root / 'app/artifacts.tsv'
            other = 'resource\tRuntime/keep.dll\t4\tkeep-hash\tpe\tkeep.dll\tP2'
            manifest.write_text('link\tlib/libntdll_unix.a\t1\told\tunix\tmythic/app/Madeira/libntdll_unix.a\tP3\n' + other + '\n')
            with patch.object(m, 'REPO', root):
                m.refresh_record(archive)
                lines = manifest.read_text().splitlines()
                self.assertEqual(lines[1], other)
                self.assertEqual(lines[0].split('\t')[2:4], [str(archive.stat().st_size), hashlib.sha256(archive.read_bytes()).hexdigest()])
                self.assertEqual((root / 'app/Sources/S1Probe/Runtime/artifacts.tsv').read_bytes(), manifest.read_bytes())
                manifest.write_text(other + '\n')
                with self.assertRaisesRegex(ValueError, 'expected one'):
                    m.refresh_record(archive)
