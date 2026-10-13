# SPDX-License-Identifier: GPL-3.0-or-later
"""Use the Swift frontend's builtin headers, independent of native-build Clang."""
import json
import os
from pathlib import Path
import shutil
import subprocess


def stage(sdk: Path, resource: Path) -> None:
    source = (resource / 'clang/include').resolve(strict=True)
    for name in ('arm_neon.h', 'module.modulemap', 'stddef.h'):
        if not (source / name).is_file():
            raise ValueError(f'Swift builtin header missing: {source / name}')
    # Swift's resource directory may be a symlink into lib/clang/<version>.
    # SDK interfaces can refer to that canonical module map directly.
    version = source.parent.name
    if not version or not all(c.isdigit() or c == '.' for c in version):
        raise ValueError(f'Unrecognized Swift Clang resource version: {source}')
    sdk = sdk.resolve(strict=True)
    lib = sdk / 'Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib'
    if not lib.is_dir():
        raise ValueError(f'Not an installed Darwin SDK: {sdk}')
    targets = [lib / 'clang' / version / 'include', lib / 'swift/clang/include']
    for target in targets:
        # Do not follow an SDK symlink outside the SDK during replacement.
        if not target.parent.resolve().is_relative_to(sdk):
            raise ValueError(f'SDK header path escapes bundle: {target}')
        if target.is_symlink():
            target.unlink()
        elif target.exists():
            shutil.rmtree(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, target)
        for name in ('arm_neon.h', 'module.modulemap', 'stddef.h'):
            if (target / name).read_bytes() != (source / name).read_bytes():
                raise ValueError(f'Swift builtin header copy mismatch: {target / name}')
        print(f'Swift Clang {version} builtin headers: {target}', flush=True)


if __name__ == '__main__':
    info = json.loads(subprocess.check_output(['swiftc', '-print-target-info']))
    # Same selection as xtool upstream fix #274. PATH clang remains LLVM 22
    # for Wine/Mesa; only Swift's imported builtin headers are replaced.
    stage(Path(os.environ['DARWIN_SDK']), Path(info['paths']['runtimeResourcePath']))
