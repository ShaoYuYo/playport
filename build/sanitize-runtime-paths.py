#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Remove this workstation's path from staged native diagnostic strings.

Native DLLs can retain __FILE__ strings from dependencies and toolchain CRTs
outside their component's prefix-map root.  Replace only the exact workstation
prefix, preserving byte offsets and file sizes, then refresh resource hashes.
"""
import hashlib
from pathlib import Path
import shutil

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / 'app/artifacts.tsv'
RUNTIME = REPO / 'app/Sources/S1Probe/Runtime'
DXMT = REPO / '.work/run/dxmt-patched/pe'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replacement(prefix):
    marker = b'./'
    if len(prefix) < len(marker):
        raise ValueError('workstation prefix is too short')
    return marker + b'_' * (len(prefix) - len(marker))


def sanitize(repo=REPO, prefix=None):
    repo = Path(repo)
    manifest = repo / 'app/artifacts.tsv'
    runtime = repo / 'app/Sources/S1Probe/Runtime'
    dxmt = repo / '.work/run/dxmt-patched/pe'
    prefix = prefix or (str(Path.home()) + '/').encode()
    changed = {}
    for path in sorted(runtime.rglob('*')):
        if not path.is_file() or path.name == 'artifacts.tsv':
            continue
        data = path.read_bytes()
        count = data.count(prefix)
        if count:
            clean = data.replace(prefix, replacement(prefix))
            if len(clean) != len(data):
                raise ValueError(f'path sanitization changed file size: {path}')
            path.write_bytes(clean)
            changed[str(path.relative_to(runtime))] = count

    lines = manifest.read_text().splitlines(keepends=True)
    out = []
    for line in lines:
        if not line or line.startswith('#'):
            out.append(line)
            continue
        row = line.rstrip('\n').split('\t')
        if len(row) != 7:
            raise ValueError(f'malformed artifacts.tsv row: {line!r}')
        kind, dest, size, old_digest, root, source, provenance = row
        if kind == 'resource':
            path = runtime / dest.removeprefix('Runtime/')
            if not path.is_file():
                raise ValueError(f'missing staged resource: {path}')
            row[2:4] = [str(path.stat().st_size), digest(path)]
            if provenance == 'P5-dxmt-pe' and dest.removeprefix('Runtime/') in changed:
                arch_name = Path(dest.removeprefix('Runtime/'))
                mirror = dxmt / arch_name
                if not mirror.is_file():
                    raise ValueError(f'missing DXMT verification copy: {mirror}')
                shutil.copyfile(path, mirror)
        out.append('\t'.join(row) + '\n')
    manifest.write_text(''.join(out))
    shutil.copyfile(manifest, runtime / 'artifacts.tsv')

    remaining = []
    for path in sorted(runtime.rglob('*')):
        if path.is_file() and prefix in path.read_bytes():
            remaining.append(str(path.relative_to(runtime)))
    if remaining:
        raise ValueError(f'workstation path remains in staged runtime: {remaining[:5]}')
    print(f"Sanitized workstation paths: {len(changed)} files, {sum(changed.values())} occurrences.")
    return changed


if __name__ == '__main__':
    sanitize()
