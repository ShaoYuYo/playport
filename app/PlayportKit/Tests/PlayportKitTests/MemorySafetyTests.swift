// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import PlayportKit

final class MemorySafetyTests: XCTestCase {
    func testDynamicTargetAndSystemCeiling() {
        XCTAssertEqual(MemorySafety.targetMB(used: 800, limit: 3072, margin: 100), 900)
        XCTAssertEqual(MemorySafety.targetMB(used: 400, limit: 3072, margin: 100), 500)
        XCTAssertEqual(MemorySafety.targetMB(used: 3050, limit: 3072, margin: 100), 3072)
        XCTAssertEqual(MemorySafety.targetMB(used: Int.max, limit: nil, margin: 100), Int.max)
    }
    func testMarginBoundsAndEarlyWarning() {
        XCTAssertEqual(MemorySafety.margin(-1), 0)
        XCTAssertEqual(MemorySafety.margin(Int.max), 1024)
        XCTAssertTrue(MemorySafety.shouldWarn(available: 199, margin: 100))
        XCTAssertFalse(MemorySafety.shouldWarn(available: 200, margin: 100))
        XCTAssertTrue(MemorySafety.shouldWarn(available: 500, margin: 300))
    }
}
