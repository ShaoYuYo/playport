// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Public build identity travels with every log, including post-game restarts.
enum AppBuild {
    static let revision = "SteamGlass-20261018-r28"
    static var summary: String {
        var lines = ["build: revision=\(revision) ui=shared-glass-sidebar cpuid=ios-index-0 vm=subpage-v1 arena=subgig-v1 root=handoff-v2 memory=safety-v1 menu=shared-v2 economy=senren-v1 callret=prediction4-v2 callback=guard-v1 exception=seh-v2 suspend=gate-v1 scratch=reuse-v1 init=oom-v1 rpm=span2-v1 lists=head-v1"]
        if let runtime = Manifest.runtime,
           let records = try? String(contentsOf: runtime.appendingPathComponent("artifacts.tsv"), encoding: .utf8) {
            for line in records.split(separator: "\n") {
                let fields = line.split(separator: "\t")
                if fields.count >= 4, ["lib/libntdll_unix.a", "Runtime/aarch64-windows/wow64win.dll", "Runtime/arm64ec-windows/ntdll.dll", "Runtime/aarch64-windows/wow64.dll", "Runtime/aarch64-windows/xtajit.dll", "Runtime/arm64ec-windows/xtajit64.dll"].contains(String(fields[1])) {
                    let name = (String(fields[1]) as NSString).lastPathComponent
                    lines.append("build: \(name) bytes=\(fields[2]) sha256=\(fields[3])")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
