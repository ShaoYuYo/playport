// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import HostIOKit

final class RenderTouchTests: XCTestCase {
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
}
