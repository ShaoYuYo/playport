# SPDX-License-Identifier: GPL-3.0-or-later
"""An app-only retry must reject stale, missing and changed native bytes."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('checkpoint', REPO / 'build/runtime-checkpoint.py')
checkpoint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checkpoint)

class Checkpoint(unittest.TestCase):
    def test_verified_snapshot_detects_tampering_and_missing_files(self):
        scratch = REPO / '.work/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as temp:
            root = Path(temp)
            for name in checkpoint.ROOTS:
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(name.encode())
            checkpoint.save(root)
            checkpoint.verify(root)
            lib = root / checkpoint.ROOTS[0]
            original = lib.read_bytes()
            lib.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'mismatch'):
                checkpoint.verify(root)
            lib.write_bytes(original)
            checkpoint.verify(root)
            lib.unlink()
            with self.assertRaisesRegex(ValueError, 'missing'):
                checkpoint.verify(root)

    def test_untracked_native_file_cannot_sneak_into_snapshot(self):
        scratch = REPO / '.work/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as temp:
            root = Path(temp)
            for name in checkpoint.ROOTS:
                p = root / name
                if name == 'app/Staged':
                    p.mkdir(parents=True)
                    (p / 'lib.a').write_bytes(b'verified')
                else:
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_bytes(name.encode())
            checkpoint.save(root)
            (root / 'app/Staged/unexpected.a').write_bytes(b'unexpected')
            with self.assertRaisesRegex(ValueError, 'mismatch'):
                checkpoint.verify(root)
