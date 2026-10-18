#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the production signed-path filter and its XCTest cases in a small host package.

The only installer operation this filter calls is regularFiles. Extract that
complete production function verbatim, without the unrelated Steam networking
and download pipeline, and run the unchanged public tests against real files.
"""
from pathlib import Path
import hashlib,json,subprocess

r=Path(__file__).resolve().parent.parent
out=r/'.work/signed-originals-tests'
source=r/'app/SteamClient/Sources/SteamClientKit/Install'
tests=r/'app/SteamClient/Tests/SteamClientKitTests'
for p in [out/'Sources/SteamClientKit',out/'Tests/SteamClientKitTests']:p.mkdir(parents=True,exist_ok=True)
model=(source/'SignedOriginals.swift').read_bytes()
fixtures=(tests/'SignedOriginalsTests.swift').read_bytes()
(out/'Sources/SteamClientKit/SignedOriginals.swift').write_bytes(model)
(out/'Tests/SteamClientKitTests/SignedOriginalsTests.swift').write_bytes(fixtures)
installer=(source/'TitleInstaller.swift').read_text()
start=installer.index('    static func regularFiles(under root: URL)');end=installer.index('\n    }',start)+6
enumeration=installer[start:end]
(out/'Sources/SteamClientKit/TitleInstaller.swift').write_text('import Foundation\nenum TitleInstaller {\n'+enumeration+'\n}\n')
support=(tests/'InstallTests.swift').read_text()
start=support.index('func scratchDir(');end=support.index('\n}',start)+2
(out/'Tests/SteamClientKitTests/Support.swift').write_text('import Foundation\n'+support[start:end]+'\n')
(out/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SignedOriginalsCheck", targets: [
 .target(name: "SteamClientKit"),
 .testTarget(name: "SteamClientKitTests", dependencies: ["SteamClientKit"])
])
''')
print(json.dumps(dict(model_sha256=hashlib.sha256(model).hexdigest(),tests_sha256=hashlib.sha256(fixtures).hexdigest(),
                      enumeration_sha256=hashlib.sha256(enumeration.encode()).hexdigest())),flush=True)
subprocess.run(['swift','test','-j','3','--package-path',str(out)],cwd=r,check=True)
