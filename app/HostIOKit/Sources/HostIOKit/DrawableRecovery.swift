// SPDX-License-Identifier: GPL-3.0-or-later
public struct DrawableRecovery: Sendable {
    public private(set) var consecutiveFailures = 0
    public init() {}
    /// A missing surface must not turn a render thread into a busy poll.
    public mutating func returned(succeeded: Bool) -> (delay: Double, report: Bool) {
        if succeeded { consecutiveFailures = 0; return (0, false) }
        consecutiveFailures = min(consecutiveFailures + 1, 1_000_000)
        let n = consecutiveFailures
        return (min(1.0 / 30, Double(n) / 1000), n == 1 || n == 16 || n == 256 || n % 2048 == 0)
    }
    public static func canRegister(width: Double, height: Double, pixelsWide: Double,
                                   pixelsHigh: Double, hasDevice: Bool, inWindow: Bool) -> Bool {
        hasDevice && inWindow && [width, height, pixelsWide, pixelsHigh].allSatisfy { $0.isFinite && $0 > 0 }
    }
}
