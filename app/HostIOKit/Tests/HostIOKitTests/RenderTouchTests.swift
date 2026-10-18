// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import HostIOKit

final class RenderTouchTests: XCTestCase {
    func testFullWindowRenderingRemovesVerticalSafeAreaBarsWithoutMovingControls() {
        for (left, right) in [(47.0, 0.0), (0.0, 47.0)] {
            for (contentWidth, contentHeight) in [(1280.0, 720.0), (2338.0, 1080.0)] {
                let old = GameViewport(width: 844, height: 390, top: 4, left: left + 4,
                    bottom: 25, right: right + 4, contentWidth: contentWidth, contentHeight: contentHeight, docked: false)
                let full = GameViewport(width: 844, height: 390, top: 4, left: left + 4,
                    bottom: 25, right: right + 4, contentWidth: contentWidth, contentHeight: contentHeight,
                    docked: false, edgeToEdge: true)
                XCTAssertEqual(full.safe, old.safe)
                XCTAssertEqual(full.game.midY, 195, accuracy: 0.001)
                // The native monitor ratio differs slightly from this window.
                XCTAssertLessThan(full.game.minY, 0.1)
                XCTAssertGreaterThan(full.game.maxY, 389.9)
                XCTAssertEqual(full.game.width / full.game.height, contentWidth / contentHeight, accuracy: 0.001)
                XCTAssertGreaterThan(full.game.height, old.game.height)
                for x in [0.0, 0.5, 1] {
                    let button = full.customFrame(x: x, y: 1, width: 73)
                    XCTAssertEqual(button, old.customFrame(x: x, y: 1, width: 73))
                    XCTAssertTrue(full.safe.contains(button))
                }
                let center = SurfacePointer.fraction(x: full.game.width / 2, y: full.game.height / 2,
                    width: full.game.width, height: full.game.height,
                    contentWidth: contentWidth, contentHeight: contentHeight, clamp: false)!
                XCTAssertEqual(center.0, 32768); XCTAssertEqual(center.1, 32768)
            }
        }
    }
    func testRailsStayInsideCameraInsetsAndOutsideGameOnEitherRotation() {
        for (left, right) in [(47.0, 0.0), (0.0, 47.0), (47.0, 47.0)] {
            let v = GameViewport(width: 844, height: 390, top: 4, left: left + 4,
                bottom: 25, right: right + 4, contentWidth: 1280, contentHeight: 720, docked: true)
            XCTAssertGreaterThanOrEqual(v.game.minX, v.leftRail.maxX)
            XCTAssertLessThanOrEqual(v.game.maxX, v.rightRail.minX)
            XCTAssertEqual(v.game.width / v.game.height, 16.0 / 9, accuracy: 0.001)
            for i in 0..<v.pageSize {
                let frame = v.controlFrame(index: i)
                XCTAssertTrue(v.safe.contains(frame))
                XCTAssertFalse(frame.intersects(v.game))
                XCTAssertGreaterThanOrEqual(frame.width, 44)
                XCTAssertGreaterThanOrEqual(frame.height, 44)
            }
        }
    }

    func testLetterboxCannotStartClickButDragOutStillReleases() {
        XCTAssertNil(SurfacePointer.fraction(x: 0, y: 200, width: 844, height: 390,
            contentWidth: 1280, contentHeight: 720, clamp: false))
        let middle = SurfacePointer.fraction(x: 422, y: 195, width: 844, height: 390,
            contentWidth: 1280, contentHeight: 720, clamp: false)!
        XCTAssertEqual(middle.0, 32768); XCTAssertEqual(middle.1, 32768)
        let up = SurfacePointer.fraction(x: -100, y: 800, width: 844, height: 390,
            contentWidth: 1280, contentHeight: 720, clamp: true)!
        XCTAssertEqual(up.0, 0)
        XCTAssertGreaterThan(up.1, 65000)
        XCTAssertNil(SurfacePointer.fraction(x: 0, y: 0, width: 0, height: 0,
            contentWidth: 1280, contentHeight: 720, clamp: false))
    }

    func testCustomControlsClampToSafeCanvas() {
        let v = GameViewport(width: 844, height: 390, top: 4, left: 51, bottom: 25, right: 4,
            contentWidth: 1280, contentHeight: 720, docked: false)
        XCTAssertTrue(v.safe.contains(v.customFrame(x: -1, y: 2, width: 100)))
        for width in [48.0, 73, 108] {
            for x in [0.0, 0.3, 1] { for y in [0.0, 0.7, 1] {
                let f = v.customFrame(x: x, y: y, width: width)
                let p = v.customPosition(origin: f.origin, width: width)
                XCTAssertEqual(p.x, x, accuracy: 0.0001)
                XCTAssertEqual(p.y, y, accuracy: 0.0001)
                XCTAssertTrue(v.safe.contains(f))
            } }
        }
    }

    func testMeasuredFramesAndDrawableWaitDoNotClaimRequestedFPS() {
        var health = FrameHealth()
        for n in 0..<30 {
            let time = Double(n) / 30
            health.drawable(at: time, wait: 0.002, succeeded: true)
            health.presented(at: time)
        }
        let sample = health.sample(at: 1)!
        XCTAssertEqual(sample.fps, 30, accuracy: 0.001)
        XCTAssertEqual(sample.frames, 30)
        XCTAssertEqual(sample.averageDrawableWaitMS, 2, accuracy: 0.001)
        XCTAssertEqual(sample.longGaps, 0)
        health.drawable(at: 1, wait: 0.3, succeeded: false)
        health.presented(at: 1.3)
        let stall = health.sample(at: 2)!
        XCTAssertEqual(stall.failedDrawables, 1)
        XCTAssertEqual(stall.longGaps, 1)
        XCTAssertEqual(stall.maximumDrawableWaitMS, 300, accuracy: 0.001)
    }

    func testEqualAverageFPSSeparatesSteadyFramesFromUnevenPresentation() {
        var steady = FrameHealth(), uneven = FrameHealth()
        for n in 0..<30 {
            let time = Double(n) / 30
            steady.requested(at: time); steady.presented(at: time)
            let irregular = time + (n.isMultiple(of: 2) ? 0 : 0.025)
            uneven.requested(at: irregular); uneven.presented(at: irregular)
        }
        let a = steady.sample(at: 1)!, b = uneven.sample(at: 1)!
        XCTAssertEqual(a.fps, b.fps)
        XCTAssertEqual(a.averagePresentationGapMS, 1000 / 30, accuracy: 0.001)
        XCTAssertEqual(a.presentationJitterMS, 0, accuracy: 0.001)
        XCTAssertGreaterThan(b.presentationJitterMS, 24)
        XCTAssertGreaterThan(b.maximumRequestGapMS, 58)
        // A late callback must not move the previous presentation backwards.
        steady.presented(at: 0.5); steady.presented(at: 1)
        let next = steady.sample(at: 2)!
        XCTAssertEqual(next.maximumGapMS, 1000 / 30, accuracy: 0.001)
        XCTAssertEqual(next.presentationJitterMS, 0, accuracy: 0.001)
    }
    func testSlowProducerAndDrawableBackpressureRemainSeparate() {
        var h = FrameHealth()
        for n in 0..<30 {
            let t = Double(n) / 30
            h.requested(at: t); h.drawable(at: t, wait: 0.001, succeeded: true); h.presented(at: t + 0.002)
        }
        let s = h.sample(at: 1)!
        XCTAssertEqual(s.averageRequestGapMS, 1000 / 30, accuracy: 0.001)
        XCTAssertEqual(s.averageDrawableWaitMS, 1, accuracy: 0.001)
        h.requested(at: 0.5) // late instrumentation cannot rewind the request clock
        h.requested(at: 1)
        let next = h.sample(at: 2)!
        XCTAssertEqual(next.averageRequestGapMS, 1000 / 30, accuracy: 0.001)
    }

    func testProducerGapExcludesDrawableAndLimiterWaitsAcrossSamples() {
        var h = FrameHealth()
        h.requested(at: 0)
        h.drawable(at: 0.005, wait: 0.010, succeeded: true, pacerWait: 0.005)
        h.requested(at: 0.020) // only 5 ms outside the previous drawable call
        h.drawable(at: 0.025, wait: 0.010, succeeded: true, pacerWait: 0.005)
        let first = h.sample(at: 1)!
        XCTAssertEqual(first.averageProducerGapMS, 5, accuracy: 0.0001)
        XCTAssertEqual(first.maximumProducerGapMS, 5, accuracy: 0.0001)
        XCTAssertEqual(first.averageDrawableWaitMS, 10, accuracy: 0.0001)
        XCTAssertEqual(first.averagePacerWaitMS, 5, accuracy: 0.0001)
        h.requested(at: 1.1)
        let next = h.sample(at: 2)!
        XCTAssertEqual(next.averageProducerGapMS, 1065, accuracy: 0.0001)
        XCTAssertEqual(next.maximumProducerGapMS, 1065, accuracy: 0.0001)
        XCTAssertEqual(next.averageDrawableWaitMS, 0)
    }

    func testProcessCPUUsesItsOwnSampleWindowAndSupportsMultipleCores() {
        var h = FrameHealth()
        h.requested(at: 0)
        XCTAssertNil(h.sample(at: 1, cpuSeconds: 10)!.processCPUPercent)
        XCTAssertEqual(h.sample(at: 3, cpuSeconds: 15)!.processCPUPercent!, 250, accuracy: 0.0001)
        XCTAssertNil(h.sample(at: 4, cpuSeconds: 1)!.processCPUPercent) // counter reset
        XCTAssertNil(h.sample(at: 5, cpuSeconds: .nan)!.processCPUPercent)
        XCTAssertNil(h.sample(at: 6, cpuSeconds: 2)!.processCPUPercent)
        XCTAssertEqual(h.sample(at: 7, cpuSeconds: 2)!.processCPUPercent, 0)
    }

}
