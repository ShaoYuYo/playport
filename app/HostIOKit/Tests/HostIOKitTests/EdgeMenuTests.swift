// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import HostIOKit

final class EdgeMenuTests: XCTestCase {
    func testOneTapOpensBothHiddenAndVisibleMenu() {
        var menu = EdgeMenuVisibility()
        menu.configure(active: true, autoHide: true, editing: false, now: 0)
        menu.expire(now: 3)
        XCTAssertFalse(menu.shown); XCTAssertNil(menu.deadline)
        menu.begin(now: 4)
        XCTAssertTrue(menu.shown); XCTAssertNil(menu.deadline)
        XCTAssertTrue(menu.end(inside: true, now: 4.1))
        XCTAssertFalse(menu.end(inside: true, now: 4.15)) // no duplicate activation
        menu.begin(now: 4.2)
        XCTAssertTrue(menu.end(inside: true, now: 4.3))
    }

    func testRepeatedViewUpdatesDoNotRevealHiddenButtonOrPostponeDeadline() {
        var menu = EdgeMenuVisibility()
        menu.configure(active: true, autoHide: true, editing: false, now: 0)
        menu.configure(active: true, autoHide: true, editing: false, now: 2)
        XCTAssertEqual(menu.deadline, 2.5)
        menu.expire(now: 3)
        menu.configure(active: true, autoHide: true, editing: false, now: 10)
        XCTAssertFalse(menu.shown); XCTAssertNil(menu.deadline)
    }

    func testHeldAndHoveredControlsDoNotDisappearAndCancelledTouchDoesNotOpen() {
        var menu = EdgeMenuVisibility()
        menu.configure(active: true, autoHide: true, editing: false, now: 0)
        menu.begin(now: 1); menu.expire(now: 100)
        XCTAssertTrue(menu.shown)
        XCTAssertFalse(menu.end(inside: false, now: 101))
        menu.hover(true, now: 102); menu.expire(now: 200)
        XCTAssertTrue(menu.shown); XCTAssertNil(menu.deadline)
        menu.hover(false, now: 201); menu.expire(now: 204)
        XCTAssertFalse(menu.shown)
    }

    func testEditingAlwaysShownAndDisablingHidingImmediatelyRestoresButton() {
        var menu = EdgeMenuVisibility()
        menu.configure(active: true, autoHide: true, editing: true, now: 0)
        menu.expire(now: 100); XCTAssertTrue(menu.shown); XCTAssertNil(menu.deadline)
        menu.configure(active: true, autoHide: true, editing: false, now: 101)
        menu.expire(now: 104); XCTAssertFalse(menu.shown)
        menu.configure(active: true, autoHide: false, editing: false, now: 105)
        XCTAssertTrue(menu.shown); XCTAssertNil(menu.deadline)
    }

    func testClosingCancelsInteractionAndReopeningGetsAFreshDeadline() {
        var menu = EdgeMenuVisibility()
        menu.configure(active: true, autoHide: true, editing: false, now: 0)
        menu.hover(true, now: 1)
        menu.configure(active: false, autoHide: true, editing: false, now: 2)
        XCTAssertFalse(menu.shown); XCTAssertNil(menu.deadline)
        XCTAssertFalse(menu.end(inside: true, now: 3))
        menu.configure(active: true, autoHide: true, editing: false, now: 4)
        XCTAssertEqual(menu.deadline, 6.5)
    }

    func testMenuStaysAtSafeTopRightAcrossRotationAndGameResolution() {
        for (left, right) in [(47.0, 0.0), (0.0, 47.0), (47.0, 47.0)] {
            var previous: CGRect?
            for monitor in [(1280.0, 720.0), (2338.0, 1080.0)] {
                let v = GameViewport(width: 844, height: 390, top: 4, left: left + 4, bottom: 25, right: right + 4,
                    contentWidth: monitor.0, contentHeight: monitor.1, docked: false, edgeToEdge: true)
                let frame = v.menuFrame()
                XCTAssertTrue(v.safe.contains(frame)); XCTAssertEqual(frame.width, 48)
                XCTAssertEqual(frame.height, 48)
                XCTAssertEqual(frame.maxX, v.safe.maxX)
                XCTAssertEqual(frame.minY, v.safe.minY)
                if let previous { XCTAssertEqual(frame, previous) }
                previous = frame
                XCTAssertEqual(v.game.midY, 195, accuracy: 0.001)
            }
        }
    }

    func testDisabledMenuCannotReactToStaleTouchOrHover() {
        var menu = EdgeMenuVisibility()
        menu.configure(active: true, autoHide: true, editing: false, now: 0)
        menu.begin(now: 1)
        menu.configure(active: false, autoHide: true, editing: false, now: 1.1)
        menu.hover(true, now: 1.2)
        menu.begin(now: 1.3)
        XCTAssertFalse(menu.end(inside: true, now: 1.4))
        XCTAssertFalse(menu.shown); XCTAssertNil(menu.deadline)
        menu.configure(active: true, autoHide: true, editing: false, now: 4)
        XCTAssertEqual(menu.deadline, 6.5)
    }
}
