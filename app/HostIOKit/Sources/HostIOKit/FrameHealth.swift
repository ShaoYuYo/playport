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
        public let averagePacerWaitMS: Double
        public let maximumPacerWaitMS: Double
        public let averagePresentationGapMS: Double
        public let presentationJitterMS: Double
        public let maximumRequestGapMS: Double
        public let averageRequestGapMS: Double
        /// From drawable return until the next request. Includes guest work,
        /// submission and other waits; this is not a pure CPU or GPU timer.
        public let averageProducerGapMS: Double
        public let maximumProducerGapMS: Double
        /// All process threads combined: 100% means one fully occupied core.
        public let processCPUPercent: Double?
    }
    private var start: Double?
    private var previous: Double?
    private var frames = 0, gaps = 0, calls = 0, failures = 0
    private var maxGap = 0.0, totalWait = 0.0, maxWait = 0.0
    private var totalPacerWait = 0.0, maxPacerWait = 0.0
    private var lastRequest: Double?, requestGap = 0.0
    private var requestGaps = 0, requestTotal = 0.0
    private var gapCount = 0, gapMean = 0.0, gapM2 = 0.0
    private var lastReturn: Double?, producerTotal = 0.0, producerMax = 0.0
    private var producerGaps = 0
    private var cpuBaseline: (time: Double, seconds: Double)?
    public init() {}

    /// Arrival before limiter/drawable waits: distinguishes a slow producer
    /// from time spent waiting for the frame limiter or the GPU surface.
    public mutating func requested(at time: Double) {
        if start == nil { start = time }
        if let lastReturn, time >= lastReturn {
            let gap = time - lastReturn
            producerTotal += gap; producerMax = max(producerMax, gap); producerGaps += 1
        }
        lastReturn = nil
        if let lastRequest, time >= lastRequest {
            let gap = time - lastRequest
            requestGap = max(requestGap, gap); requestTotal += gap; requestGaps += 1
        }
        lastRequest = max(time, lastRequest ?? time)
    }

    public mutating func drawable(at time: Double, wait: Double, succeeded: Bool, pacerWait: Double = 0) {
        if start == nil { start = time }
        calls += 1
        let duration = max(0, wait)
        lastReturn = max(time + duration, lastReturn ?? (time + duration))
        totalWait += duration
        maxWait = max(maxWait, duration)
        totalPacerWait += max(0, pacerWait)
        maxPacerWait = max(maxPacerWait, max(0, pacerWait))
        if !succeeded { failures += 1 }
    }
    public mutating func presented(at time: Double) {
        if start == nil { start = time }
        if let previous, time >= previous {
            let gap = time - previous
            maxGap = max(maxGap, gap)
            if gap > 0.05 { gaps += 1 }
            gapCount += 1
            let delta = gap - gapMean
            gapMean += delta / Double(gapCount)
            gapM2 += delta * (gap - gapMean)
        }
        previous = max(time, previous ?? time)
        frames += 1
    }
    public mutating func sample(at time: Double, cpuSeconds: Double? = nil) -> Sample? {
        guard let start, time - start >= 1 else { return nil }
        var cpuPercent: Double?
        if let cpuSeconds, cpuSeconds.isFinite, cpuSeconds >= 0 {
            if let baseline = cpuBaseline, time > baseline.time, cpuSeconds >= baseline.seconds {
                cpuPercent = (cpuSeconds - baseline.seconds) * 100 / (time - baseline.time)
            }
            cpuBaseline = (time, cpuSeconds)
        } else {
            cpuBaseline = nil
        }
        let result = Sample(fps: Double(frames) / (time - start), frames: frames, longGaps: gaps,
            maximumGapMS: maxGap * 1000,
            averageDrawableWaitMS: calls > 0 ? totalWait * 1000 / Double(calls) : 0,
            maximumDrawableWaitMS: maxWait * 1000, failedDrawables: failures,
            averagePacerWaitMS: calls > 0 ? totalPacerWait * 1000 / Double(calls) : 0,
            maximumPacerWaitMS: maxPacerWait * 1000,
            averagePresentationGapMS: gapMean * 1000,
            presentationJitterMS: gapCount > 0 ? (max(0, gapM2) / Double(gapCount)).squareRoot() * 1000 : 0,
            maximumRequestGapMS: requestGap * 1000,
            averageRequestGapMS: requestGaps > 0 ? requestTotal * 1000 / Double(requestGaps) : 0,
            averageProducerGapMS: producerGaps > 0 ? producerTotal * 1000 / Double(producerGaps) : 0,
            maximumProducerGapMS: producerMax * 1000, processCPUPercent: cpuPercent)
        self.start = time
        frames = 0; gaps = 0; calls = 0; failures = 0
        maxGap = 0; totalWait = 0; maxWait = 0
        totalPacerWait = 0; maxPacerWait = 0
        gapCount = 0; gapMean = 0; gapM2 = 0; requestGap = 0
        requestGaps = 0; requestTotal = 0
        producerTotal = 0; producerMax = 0; producerGaps = 0
        return result
    }
}
