# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('sanitize_paths', REPO / 'build/sanitize-runtime-paths.py')
paths = importlib.util.module_from_spec(spec)
spec.loader.exec_module(paths)


class SanitizeRuntimePaths(unittest.TestCase):
    def test_same_size_hashes_and_dxmt_verification_copy(self):
        scratch = REPO / '.work/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as temp:
            root = Path(temp)
            runtime = root / 'app/Sources/S1Probe/Runtime'
            dxmt = root / '.work/run/dxmt-patched/pe/aarch64-windows/d3d11.dll'
            steam = runtime / 'steamapi/i386-windows/steam_api.dll'
            staged_dxmt = runtime / 'aarch64-windows/d3d11.dll'
            for p in (steam, staged_dxmt, dxmt):
                p.parent.mkdir(parents=True, exist_ok=True)
            prefix = b'/' + b'home' + b'/' + b'runner' + b'/'
            steam.write_bytes(b'A' + prefix + b'work/source.cpp\0B')
            staged_dxmt.write_bytes(b'C' + prefix + b'work/dxmt.cpp\0D')
            dxmt.write_bytes(staged_dxmt.read_bytes())
            manifest = root / 'app/artifacts.tsv'
            reference = root / 'build/dxmt-command-inlined.metal'
            reference.parent.mkdir(parents=True)
            reference.write_bytes(b'pinned expanded Metal source')
            old_msl = paths.MSL_SHA256
            paths.MSL_SHA256 = hashlib.sha256(reference.read_bytes()).hexdigest()
            self.addCleanup(setattr, paths, 'MSL_SHA256', old_msl)
            manifest.write_text(
                '# fixture\n'
                'resource\tRuntime/steamapi/i386-windows/steam_api.dll\t0\told\tsteamapi\tx\tP8-steamapi\n'
                'resource\tRuntime/aarch64-windows/d3d11.dll\t0\told\tdxmt-pe\tx\tP5-dxmt-pe\n'
                'gap\tRuntime/absent.dll\t-\t-\t-\toptional\ttest\n')
            sizes = [steam.stat().st_size, staged_dxmt.stat().st_size]
            changed = paths.sanitize(root, prefix)
            self.assertEqual(set(changed), {
                'steamapi/i386-windows/steam_api.dll', 'aarch64-windows/d3d11.dll'})
            self.assertEqual(sizes, [steam.stat().st_size, staged_dxmt.stat().st_size])
            self.assertNotIn(prefix, steam.read_bytes() + staged_dxmt.read_bytes())
            self.assertEqual(dxmt.read_bytes(), staged_dxmt.read_bytes())
            text = manifest.read_text()
            self.assertIn(hashlib.sha256(steam.read_bytes()).hexdigest(), text)
            self.assertIn(hashlib.sha256(staged_dxmt.read_bytes()).hexdigest(), text)
            self.assertEqual((runtime / 'artifacts.tsv').read_text(), text)
            for arch in ('aarch64', 'arm64ec'):
                restored = root / f'.work/run/dxmt-patched/build-{arch}/src/dxmt/dxmt_command.metal'
                self.assertEqual(restored.read_bytes(), reference.read_bytes())
            self.assertEqual(paths.sanitize(root, prefix), {})
