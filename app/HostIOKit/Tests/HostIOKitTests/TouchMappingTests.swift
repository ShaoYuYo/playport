// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import HostIOKit

final class TouchMappingTests: XCTestCase {
    func testHardwareAndTwoFingersShareOneHeldKey() {
        var state = InputOwners()
        XCTAssertTrue(state.update(code: 0xa2, source: "finger1", down: true))
        XCTAssertFalse(state.update(code: 0xa2, source: "finger1", down: true))
        XCTAssertFalse(state.update(code: 0xa2, source: "finger2", down: true))
        XCTAssertFalse(state.update(code: 0xa2, source: "hardware", down: true))
        XCTAssertFalse(state.update(code: 0xa2, source: "finger1", down: false))
        XCTAssertFalse(state.update(code: 0xa2, source: "hardware", down: false))
        XCTAssertTrue(state.update(code: 0xa2, source: "finger2", down: false))
        XCTAssertFalse(state.update(code: 0xa2, source: "finger2", down: false))
    }

    func testFocusOrMenuReleaseCannotBeUndoneByStaleFingerUp() {
        var state = InputOwners(), lifecycle = Lifecycle()
        XCTAssertTrue(state.update(code: 0x20, source: "touch", down: true))
        XCTAssertTrue(lifecycle.keyDown(0x20))
        XCTAssertTrue(lifecycle.buttonDown(upFlag: Pointer.leftUp))
        let actions = lifecycle.handle(.menuOpened)
        XCTAssertEqual(actions, [.releaseKeys([0x20]), .releaseButtons([Pointer.leftUp]), .suspendAudio(deactivate: false)])
        state.clear()
        XCTAssertFalse(state.update(code: 0x20, source: "touch", down: false))
        XCTAssertEqual(lifecycle.heldKeys, [])
        XCTAssertEqual(lifecycle.handle(.menuClosed), [.resumeAudio])
        XCTAssertTrue(state.update(code: 0x20, source: "newTouch", down: true))
        XCTAssertTrue(lifecycle.keyDown(0x20))
    }

    func testAllKeyboardBindingsUseSupportedHIDCodes() {
        for action in TouchAction.allCases where action != .mouseLeft && action != .mouseRight {
            XCTAssertNotNil(action.hidUsage.flatMap { KeyMap.virtualKey(hidUsage: $0) }, action.rawValue)
        }
        XCTAssertEqual(KeyMap.virtualKey(hidUsage: TouchAction.control.hidUsage!), 0xa2)
        XCTAssertEqual(KeyMap.virtualKey(hidUsage: TouchAction.key0.hidUsage!), 0x30)
        XCTAssertEqual(KeyMap.virtualKey(hidUsage: TouchAction.f12.hidUsage!), 0x7b)
    }

    func testPersistentLayoutRoundTripAndInvalidCoordinates() throws {
        var layout = TouchLayout()
        layout.buttons = [.init(action: .control, x: 0.2, y: 0.5), .init(action: .enter, x: 0.8, y: 0.5)]
        layout.enabled = true
        layout.buttons[0].label = "快轉"
        layout.buttons[0].x = -8
        layout.buttons[1].y = 30
        layout.buttons.append(layout.buttons[0])
        let saved = try JSONEncoder().encode(layout.normalized)
        let restored = try JSONDecoder().decode(TouchLayout.self, from: saved)
        XCTAssertTrue(restored.enabled)
        XCTAssertEqual(restored.buttons.count, 2)
        XCTAssertEqual(restored.buttons[0].x, 0)
        XCTAssertEqual(restored.buttons[1].y, 1)
        XCTAssertEqual(restored.buttons[0].label, "快轉")
        layout.opacity = .nan
        layout.buttons[0].x = .infinity
        XCTAssertEqual(layout.normalized.opacity, 0.72)
        XCTAssertEqual(layout.normalized.buttons[0].x, 0.5)
    }

    func testOldLayoutsGainDockingWithoutLosingThePlayersKeys() throws {
        let json = #"{"enabled":true,"opacity":0.5,"buttons":[]}"#
        let layout = try JSONDecoder().decode(TouchLayout.self, from: Data(json.utf8))
        XCTAssertTrue(layout.docked)
        XCTAssertTrue(layout.enabled)
        XCTAssertEqual(layout.buttons, [])
        XCTAssertTrue(TouchLayout().enabled)
        XCTAssertFalse(TouchLayout().docked)
        XCTAssertTrue(TouchLayout().buttons.isEmpty)
    }
}
