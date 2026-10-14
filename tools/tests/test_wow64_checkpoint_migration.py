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
            if args[0] == 'diff': return b'patches/madeira-unix/series\n'
            if args[1].endswith('patches/fex/series'):
                return (REPO / 'patches/fex/series').read_text().removesuffix(m.FEX_PATCH_NAME + '\n').encode()
            return before.encode()
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
                with self.assertRaisesRegex(ValueError, 'expected one artifact'):
                    m.refresh_record(archive)

    def test_manifest_refresh_updates_only_both_changed_outputs(self):
        scratch = REPO / '.work/tmp'; scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as t:
            root = Path(t)
            (root / 'app/Sources/S1Probe/Runtime').mkdir(parents=True)
            archive = root / 'new.a'; archive.write_bytes(b'new virtual object')
            dll = root / 'new.dll'; dll.write_bytes(b'new wow64 exports')
            manifest = root / 'app/artifacts.tsv'
            other = 'resource\tRuntime/keep.dll\t4\tkeep-hash\tpe\tkeep.dll\tP2'
            manifest.write_text('link\tlib/libntdll_unix.a\t1\told\tunix\tarchive\tP3\n'
                                'resource\tRuntime/aarch64-windows/xtajit.dll\t1\told\tfex\tdll\tP3\n' + other + '\n')
            with patch.object(m, 'REPO', root):
                m.refresh_record(archive, dll)
            rows = [line.split('\t') for line in manifest.read_text().splitlines()]
            for row, output in zip(rows[:2], (archive, dll)):
                self.assertEqual(row[2:4], [str(output.stat().st_size), hashlib.sha256(output.read_bytes()).hexdigest()])
            self.assertEqual('\t'.join(rows[2]), other)
