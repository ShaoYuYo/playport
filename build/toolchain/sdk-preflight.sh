#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Exercise xtool's own SDK discovery, SwiftUI and ld64 before building Wine.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
python3 "$HERE/sdk-clang-headers.py"
mkdir -p "$PLAYPORT_BUILD/run/logs"
status="$PLAYPORT_BUILD/run/logs/sdk-status.txt"
"$XTOOL" sdk status | tee "$status"
grep -Fq "Path: $DARWIN_SDK" "$status" || {
    echo 'xtool cannot discover DARWIN_SDK. Check XDG_CONFIG_HOME and SDK installation.' >&2
    exit 1
}
grep -Fq 'Version: epoch=2,darwinTools=1.1.0,oam=1.3.0' "$status" || {
    echo 'SDK metadata is incompatible with the pinned xtool 1.20.1.' >&2
    exit 1
}
swift sdk list | tee "$PLAYPORT_BUILD/run/logs/swift-sdk-list.txt"
grep -q darwin "$PLAYPORT_BUILD/run/logs/swift-sdk-list.txt" || {
    echo 'SwiftPM cannot discover the Darwin SDK.' >&2
    exit 1
}
probe="$PLAYPORT_BUILD/sdk-preflight"
mkdir -p "$probe/Sources/SDKProbe"
cat > "$probe/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SDKProbe", platforms: [.iOS("26.0")],
    products: [.library(name: "SDKProbe", targets: ["SDKProbe"])],
    targets: [.target(name: "SDKProbe")])
SWIFT
cat > "$probe/Sources/SDKProbe/SDKProbe.swift" <<'SWIFT'
import SwiftUI
import CoreText
enum PP {
    static let surface = Color.black
    static let line = Color.gray
}
@main struct SDKProbeApp: App {
    var body: some Scene {
        WindowGroup {
            GlassEffectContainer {
                Text("中文 / PlayPort").padding()
                    .ppGlass(cornerRadius: 12, tint: .orange)
            }
        }
    }
}
SWIFT
# Compile the real new modifier and locale mapping, not just an API lookalike.
cp "$PLAYPORT_REPO/app/Sources/S1Probe/UI/LiquidGlass.swift" "$probe/Sources/SDKProbe/LiquidGlass.swift"
cp "$PLAYPORT_REPO/app/PlayportKit/Sources/PlayportKit/GameLanguage.swift" "$probe/Sources/SDKProbe/GameLanguage.swift"
cat > "$probe/xtool.yml" <<'YAML'
version: 1
bundleID: dev.playport.sdkprobe
product: SDKProbe
YAML
(
    cd "$probe"
    SWIFTPM_CUSTOM_BIN_DIR="$PLAYPORT_REPO/build/ld64" "$XTOOL" dev build --ipa
)
test -s "$probe/xtool/SDKProbe.ipa"
echo 'SDK preflight: a real iOS SwiftUI / Liquid Glass IPA compiled and linked successfully.'
