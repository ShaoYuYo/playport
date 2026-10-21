// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import HostIOKit
final class DrawableRecoveryTests: XCTestCase {
    func testUnavailableLayerBacksOffAndSuccessResets() {
        var state = DrawableRecovery()
        XCTAssertGreaterThan(state.returned(succeeded: false).delay, 0)
        for _ in 0..<10000 { let r = state.returned(succeeded: false); XCTAssertLessThanOrEqual(r.delay, 1.0 / 30) }
        XCTAssertEqual(state.returned(succeeded: true).delay, 0)
        XCTAssertEqual(state.consecutiveFailures, 0)
        XCTAssertTrue(state.returned(succeeded: false).report)
    }
    func testRegistrationWaitsForWindowDeviceAndFiniteNonzeroSize() {
        XCTAssertTrue(DrawableRecovery.canRegister(width: 844, height: 390, pixelsWide: 2532, pixelsHigh: 1170, hasDevice: true, inWindow: true))
        XCTAssertFalse(DrawableRecovery.canRegister(width: 0, height: 390, pixelsWide: 2532, pixelsHigh: 1170, hasDevice: true, inWindow: true))
        XCTAssertFalse(DrawableRecovery.canRegister(width: 844, height: 390, pixelsWide: .nan, pixelsHigh: 1170, hasDevice: true, inWindow: true))
        XCTAssertFalse(DrawableRecovery.canRegister(width: 844, height: 390, pixelsWide: 2532, pixelsHigh: 1170, hasDevice: false, inWindow: true))
        XCTAssertFalse(DrawableRecovery.canRegister(width: 844, height: 390, pixelsWide: 2532, pixelsHigh: 1170, hasDevice: true, inWindow: false))
    }
    func testFailedAcquisitionCannotCountAsAPresentedFrame() {
        var health = FrameHealth()
        health.requested(at: 0)
        for i in 0..<1000 { health.drawable(at: Double(i) / 1000, wait: 0, succeeded: false) }
        let sample = health.sample(at: 2)
        XCTAssertEqual(sample?.frames, 0)
        XCTAssertEqual(sample?.failedDrawables, 1000)
        XCTAssertEqual(sample?.fps, 0)
    }
}
