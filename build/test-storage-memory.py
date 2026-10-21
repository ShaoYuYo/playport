#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run production storage, memory and JIT launch models with their XCTest fixtures."""
from pathlib import Path
import hashlib, json, subprocess

r = Path(__file__).resolve().parent.parent
out = r / '.work/storage-memory-tests'
hashes = {}
for folder in ['Sources/PlayportKit', 'Tests/PlayportKitTests']:
    (out / folder).mkdir(parents=True, exist_ok=True)
for folder, names in [
    ('Sources/PlayportKit', ['StorageCleanup', 'TitleMemory', 'SetupChecklist', 'JitMethod', 'JitLaunchPolicy', 'LauncherLayout']),
    ('Tests/PlayportKitTests', ['StorageCleanupTests', 'TitleMemoryTests', 'JitLaunchPreflightTests', 'LauncherLayoutTests'])]:
    for name in names:
        filename = name + '.swift'
        path = r / 'app/PlayportKit' / folder / filename
        data = path.read_bytes()
        (out / folder / filename).write_bytes(data)
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
