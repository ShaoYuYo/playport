# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('compat', REPO / 'build/rebuild-win32-compat-checkpoint.py')
compat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compat)

class WindowsCompatibilityCheckpoint(unittest.TestCase):
    def test_native_guard_accepts_reviewed_delta_and_rejects_unrelated_inputs(self):
        # The exact checked-in recipe/resource/patch delta, not a mock build.
        compat.validate_delta()
        original = compat.git
        def changed(*args):
            if args[0] == 'diff': return b'pins.lock\n'
            return original(*args)
        with patch.object(compat, 'git', side_effect=changed):
            with self.assertRaisesRegex(ValueError, 'unexpected native input'):
                compat.validate_delta()

    def test_only_bridge_records_change_and_wrong_pe_architecture_is_rejected(self):
        scratch = REPO / '.work/tests'; scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            repo = Path(tmp)
            runtime = repo / 'app/Sources/S1Probe/Runtime/aarch64-windows'; runtime.mkdir(parents=True)
            generated = repo / 'build/generated'; generated.mkdir(parents=True)
            other = 'resource\tRuntime/keep.dll\t4\tkeep-sha\tpe\tkeep.dll\tP2'
            keep = runtime / 'keep.dll'; keep.write_bytes(b'keep')
            rows = [f'resource\tRuntime/aarch64-windows/{name}\t1\told\tpe-aarch64\tdlls/{name[:-4]}/aarch64-windows/{name}\tP2'
                    for name in ('wow64.dll', 'wow64win.dll')]
            (repo / 'app/artifacts.tsv').write_text('\n'.join(rows + [other]) + '\n')
            old_generated = 'dlls/keep/aarch64-windows/keep.dll\t4\tkeep-sha\tpe\taarch64\tKeep\tyes'
            (generated / 'wine-pe-aarch64-windows.tsv').write_text('\n'.join([
                f'dlls/{name[:-4]}/aarch64-windows/{name}\t1\told\tpe\taarch64\tExport\tyes'
                for name in ('wow64.dll', 'wow64win.dll')] + [old_generated]) + '\n')
            outputs = {}
            for i, name in enumerate(('wow64.dll', 'wow64win.dll')):
                data = bytearray(512); data[:2] = b'MZ'
                struct.pack_into('<I', data, 60, 128); data[128:132] = b'PE\0\0'
                struct.pack_into('<H', data, 132, 0xaa64); data[200] = i + 1
                file = repo / name; file.write_bytes(data); outputs[name] = file
            compat.replace_records(repo, outputs)
            records = (repo / 'app/artifacts.tsv').read_text().splitlines()
            self.assertEqual(records[-1], other)
            self.assertEqual(keep.read_bytes(), b'keep')
            self.assertEqual((generated / 'wine-pe-aarch64-windows.tsv').read_text().splitlines()[-1], old_generated)
            for record, (name, file) in zip(records[:2], outputs.items()):
                self.assertEqual(record.split('\t')[2:4], [str(file.stat().st_size), hashlib.sha256(file.read_bytes()).hexdigest()])
                self.assertEqual((runtime / name).read_bytes(), file.read_bytes())
            self.assertEqual((repo / 'app/artifacts.tsv').read_bytes(), (runtime.parent / 'artifacts.tsv').read_bytes())
            bad = bytearray(outputs['wow64.dll'].read_bytes()); struct.pack_into('<H', bad, 132, 0x14c)
            outputs['wow64.dll'].write_bytes(bad)
            with self.assertRaisesRegex(ValueError, 'not aarch64 PE'):
                compat.replace_records(repo, {'wow64.dll': outputs['wow64.dll']})

if __name__ == '__main__': unittest.main()
