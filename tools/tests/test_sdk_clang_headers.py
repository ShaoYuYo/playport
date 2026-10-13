# SPDX-License-Identifier: GPL-3.0-or-later
"""Replace stale SDK builtins even when their files already exist."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('sdk_headers', REPO / 'build/toolchain/sdk-clang-headers.py')
headers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(headers)


class SDKHeaders(unittest.TestCase):
    def test_existing_and_symlinked_headers_replaced_with_swift_toolchain(self):
        scratch = REPO / '.work/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as temp:
            root = Path(temp)
            source = root / 'host/lib/clang/21/include'
            source.mkdir(parents=True)
            for name in ('arm_neon.h', 'module.modulemap', 'stddef.h'):
                (source / name).write_text(f'Swift 21 {name}')
            resource = root / 'host/lib/swift'
            resource.mkdir()
            (resource / 'clang').symlink_to('../clang/21')
            sdk = root / 'darwin.artifactbundle'
            lib = sdk / 'Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib'
            stale = lib / 'clang/21/include'
            stale.mkdir(parents=True)
            (stale / 'arm_neon.h').write_text('Clang 22 incompatible intrinsics')
            (stale / 'extra.h').write_text('obsolete')
            (lib / 'swift/clang').mkdir(parents=True)
            (lib / 'swift/clang/include').symlink_to('../../clang/21/include')
            for _ in range(2):
                headers.stage(sdk, resource)
                for dest in (stale, lib / 'swift/clang/include'):
                    self.assertEqual({p.name for p in dest.iterdir()}, {p.name for p in source.iterdir()})
                    for p in source.iterdir():
                        self.assertEqual((dest / p.name).read_bytes(), p.read_bytes())

    def test_missing_header_fails_without_replacing_sdk_files(self):
        scratch = REPO / '.work/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as temp:
            root = Path(temp)
            (root / 'host/clang/include').mkdir(parents=True)
            with self.assertRaisesRegex(ValueError, 'header missing'):
                headers.stage(root, root / 'host')
