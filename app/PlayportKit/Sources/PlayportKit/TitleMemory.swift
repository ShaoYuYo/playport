// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Measured title-specific reductions. Other games keep their existing budget.
/// The pool is fixed before JIT activation; it cannot grow during a play.
public struct TitleMemory: Equatable, Sendable {
    public static let preferenceKey = "titleMemoryEconomy"
    public let poolMB: Int?
    public let active: Bool

    public init(steamAppID: UInt32?, i386: Bool, enabled: Bool) {
        active = enabled && i386 && steamAppID == 1144400
        // Supplied startup report: head 26 + tail 33 MiB, no pool refusals.
        // Keep room for the normal 128 MiB translation buffer and later images.
        poolMB = active ? 256 : nil
    }

    public func config(over base: [String: String]) -> [String: String] {
        guard active else { return base }
        var result = base
        // All Wine processor queries and both PEBs use this existing setting.
        // A smaller automatic worker fleet also needs fewer FEX per-thread heaps.
        if result["cpu-count"] == nil { result["cpu-count"] = "2" }
        return result
    }

    public func arguments(over base: [String]) -> [String] {
        guard active else { return base }
        var result = base
        // KiriKiri's own cache policy; no game archives/config/save files change.
        for (key, value) in [("memusage", "low"), ("drawthread", "2")] {
            let option = "-" + key
            if !base.contains(where: { $0.lowercased() == option || $0.lowercased().hasPrefix(option + "=") }) {
                result.append(option + "=" + value)
            }
        }
        return result
    }
}
