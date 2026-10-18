// SPDX-License-Identifier: GPL-3.0-or-later
/// A frame rate limiter's timing: how long to hold each frame so frames start
/// on a fixed cadence. Small scheduling overruns retain phase; missed frames
/// resync without a burst of catch-up frames.
public struct FramePacer: Sendable {
    public private(set) var interval: Double
    private var next: Double?

    /// 0 or less: no limit.
    public init(fps: Int) {
        interval = fps > 0 ? 1.0 / Double(fps) : 0
    }

    /// The seconds to wait before a frame that arrives at `now` (a monotonic time in seconds).
    public mutating func delay(now: Double) -> Double {
        guard interval > 0 else { return 0 }
        guard let due = next else {
            next = now + interval
            return 0
        }
        if now >= due {
            // Resetting on every sub-millisecond overrun drifts against the
            // display's own cadence and can repeatedly miss a refresh.
            next = now - due < interval ? due + interval : now + interval
            return 0
        }
        next = due + interval
        return due - now
    }

    /// Drawable backpressure and the software limiter share one deadline.
    /// Waiting for a GPU surface must consume the planned frame budget rather
    /// than adding a second full delay before that wait.
    public static func remainingDelay(deadline: Double, now: Double) -> Double {
        guard deadline.isFinite, now.isFinite else { return 0 }
        return max(0, deadline - now)
    }
}
