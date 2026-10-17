// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Passive presentation evidence: no readback, synthetic frames or UI timer.
public struct FrameHealth: Sendable {
    public struct Sample: Sendable {
        public let fps: Double
        public let frames: Int
        public let longGaps: Int
        public let maximumGapMS: Double
        public let averageDrawableWaitMS: Double
        public let maximumDrawableWaitMS: Double
        public let failedDrawables: Int
    }
    private var start: Double?
    private var previous: Double?
    private var frames = 0, gaps = 0, calls = 0, failures = 0
    private var maxGap = 0.0, totalWait = 0.0, maxWait = 0.0
    public init() {}

    public mutating func drawable(at time: Double, wait: Double, succeeded: Bool) {
        if start == nil { start = time }
        calls += 1
        let duration = max(0, wait)
        totalWait += duration
        maxWait = max(maxWait, duration)
        if !succeeded { failures += 1 }
    }
    public mutating func presented(at time: Double) {
        if start == nil { start = time }
        if let previous, time >= previous {
            let gap = time - previous
            maxGap = max(maxGap, gap)
            if gap > 0.05 { gaps += 1 }
        }
        previous = time
        frames += 1
    }
    public mutating func sample(at time: Double) -> Sample? {
        guard let start, time - start >= 1 else { return nil }
        let result = Sample(fps: Double(frames) / (time - start), frames: frames, longGaps: gaps,
            maximumGapMS: maxGap * 1000,
            averageDrawableWaitMS: calls > 0 ? totalWait * 1000 / Double(calls) : 0,
            maximumDrawableWaitMS: maxWait * 1000, failedDrawables: failures)
        self.start = time
        frames = 0; gaps = 0; calls = 0; failures = 0
        maxGap = 0; totalWait = 0; maxWait = 0
        return result
    }
}
