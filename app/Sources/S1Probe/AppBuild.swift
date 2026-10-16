// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Public build identity travels with every log, including post-game restarts.
enum AppBuild {
    static let revision = "SteamGlass-20261016-r4"
    static var summary: String {
        var lines = ["build: revision=\(revision) ui=single-glass-rail cpuid=ios-index-0 vm=subpage-v1 arena=subgig-v1 memory=safety-v1"]
        if let runtime = Manifest.runtime,
           let records = try? String(contentsOf: runtime.appendingPathComponent("artifacts.tsv"), encoding: .utf8) {
            for line in records.split(separator: "\n") {
                let fields = line.split(separator: "\t")
                if fields.count >= 4, fields[1] == "lib/libntdll_unix.a" {
                    lines.append("build: libntdll_unix.a bytes=\(fields[2]) sha256=\(fields[3])")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
