// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Safety headroom, not a prediction or an entitlement to more physical RAM.
public enum MemorySafety {
    public static let preferenceKey = "memorySafetyHeadroomMB"
    public static let warningPreferenceKey = "memorySafetyShowWarnings"
    public static let defaultMB = 100
    public static let choices = [50, 100, 150, 200, 300, 500, 750, 1024]
    public static func margin(_ value: Int) -> Int { min(1024, max(0, value)) }
    public static func targetMB(used: Int, limit: Int?, margin: Int) -> Int {
        let used = max(0, used), reserve = Self.margin(margin)
        let target = used > Int.max - reserve ? Int.max : used + reserve
        return limit.map { min(max(0, $0), target) } ?? target
    }
    public static func shouldWarn(available: Int, margin: Int) -> Bool {
        available < Self.margin(margin) * 2
    }
}
