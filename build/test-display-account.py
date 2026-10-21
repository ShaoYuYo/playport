#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Test the production display recovery models and the account setup package."""
from pathlib import Path
import hashlib, json, subprocess
r=Path(__file__).resolve().parent.parent
out=r/'.work/display-check'
hashes={}
for folder,names in [('Sources/HostIOKit',['DrawableRecovery','FrameHealth']),('Tests/HostIOKitTests',['DrawableRecoveryTests'])]:
    (out/folder).mkdir(parents=True,exist_ok=True)
    for name in names:
        p=r/'app/HostIOKit'/folder/(name+'.swift');data=p.read_bytes()
        target=out/folder/p.name
        if not target.exists() or target.read_bytes()!=data:target.write_bytes(data)
        hashes[str(p.relative_to(r))]=hashlib.sha256(data).hexdigest()
(out/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package=Package(name:"DisplayCheck",targets:[.target(name:"HostIOKit"),.testTarget(name:"HostIOKitTests",dependencies:["HostIOKit"])])
''')
for p in (r/'app/AppleAccountKit').rglob('*.swift'):
    if '.build' not in p.parts:hashes[str(p.relative_to(r))]=hashlib.sha256(p.read_bytes()).hexdigest()
print(json.dumps(hashes),flush=True)
for package in [out,r/'app/AppleAccountKit']:
    subprocess.run(['swift','test','-j','3','--package-path',str(package)],check=True)
