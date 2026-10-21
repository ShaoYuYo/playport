// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import PlayportKit
final class LauncherLayoutTests: XCTestCase {
    func testPhoneSettingsKeepContentSpace() {
        let small = LauncherLayout(width: 568)
        XCTAssertTrue(small.stackedSettings)
        let phone = LauncherLayout(width: 720)
        XCTAssertFalse(phone.stackedSettings)
        XCTAssertGreaterThan(phone.width - phone.settingsSidebar - 20, 500)
    }
    func testPanelsStayWithinSafeWidth() {
        for width in stride(from: 0.0, through: 1400, by: 10) {
            let layout = LauncherLayout(width: width)
            XCTAssertLessThanOrEqual(layout.panelWidth, width)
            XCTAssertLessThanOrEqual(layout.panelWidth, 410)
        }
    }
    func testGridNeverUsesNegativeOrTinyCells() {
        for width in stride(from: 320.0, through: 1400, by: 8) {
            let layout = LauncherLayout(width: width)
            let cell = (width - 16 - Double(layout.libraryColumns - 1) * 14) / Double(layout.libraryColumns)
            XCTAssertGreaterThanOrEqual(cell, 136)
            XCTAssertLessThanOrEqual(layout.libraryColumns, 7)
        }
    }
    func testInvalidAndCompactWidths() {
        XCTAssertEqual(LauncherLayout(width: .nan).width, 0)
        XCTAssertEqual(LauncherLayout(width: -100).libraryColumns, 1)
        XCTAssertTrue(LauncherLayout(width: 700).stackedGame)
        XCTAssertFalse(LauncherLayout(width: 1024).stackedGame)
    }
}
