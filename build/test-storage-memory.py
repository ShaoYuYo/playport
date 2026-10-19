#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run complete production storage/memory models and their unchanged XCTest fixtures."""
from pathlib import Path
import hashlib, json, subprocess

r = Path(__file__).resolve().parent.parent
out = r / '.work/storage-memory-tests'
hashes = {}
for folder in ['Sources/PlayportKit', 'Tests/PlayportKitTests']:
    (out / folder).mkdir(parents=True, exist_ok=True)
for name in ['StorageCleanup', 'TitleMemory']:
    for origin, target in [('Sources/PlayportKit', 'Sources/PlayportKit'),
                           ('Tests/PlayportKitTests', 'Tests/PlayportKitTests')]:
        filename = name + ('Tests' if origin.startswith('Tests/') else '') + '.swift'
        path = r / 'app/PlayportKit' / origin / filename
        data = path.read_bytes()
        (out / target / filename).write_bytes(data)
        hashes[str(path.relative_to(r))] = hashlib.sha256(data).hexdigest()
(out / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "StorageMemoryCheck", targets: [
 .target(name: "PlayportKit"),
 .testTarget(name: "PlayportKitTests", dependencies: ["PlayportKit"])
])
''')
print(json.dumps(hashes), flush=True)
subprocess.run(['swift', 'test', '-j', '3', '--package-path', str(out)], cwd=r, check=True)
