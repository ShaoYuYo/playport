// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import PlayportKit

final class TitleMemoryTests: XCTestCase {
    func testScopedBudgetAndOptOut() {
        let profile = TitleMemory(steamAppID: 1144400, i386: true, enabled: true)
        XCTAssertTrue(profile.active)
        XCTAssertEqual(profile.poolMB, 256)
        XCTAssertGreaterThan(profile.poolMB!, 26 + 128 + 100)
        for other in [TitleMemory(steamAppID: nil, i386: true, enabled: true),
                      TitleMemory(steamAppID: 367520, i386: true, enabled: true),
                      TitleMemory(steamAppID: 1144400, i386: false, enabled: true),
                      TitleMemory(steamAppID: 1144400, i386: true, enabled: false)] {
            XCTAssertFalse(other.active)
            XCTAssertNil(other.poolMB)
            XCTAssertEqual(other.config(over: ["jumbo-mb": "0"]), ["jumbo-mb": "0"])
            XCTAssertEqual(other.arguments(over: ["-custom"]), ["-custom"])
        }
    }

    func testExplicitSettingsWinAndUnrelatedArgumentsSurvive() {
        let profile = TitleMemory(steamAppID: 1144400, i386: true, enabled: true)
        XCTAssertEqual(profile.config(over: [:]), ["cpu-count": "2"])
        XCTAssertEqual(profile.config(over: ["cpu-count": "4", "inproc-sync": "1"]),
                       ["cpu-count": "4", "inproc-sync": "1"])
        XCTAssertEqual(profile.arguments(over: ["-custom"]), ["-custom", "-memusage=normal", "-gclim=64", "-drawthread=2"])
        let explicit = ["-MEMUSAGE=low", "-gclim=16", "-drawthread=4", "-custom"]
        XCTAssertEqual(profile.arguments(over: explicit), explicit)
        XCTAssertEqual(profile.arguments(over: ["-memusage", "normal"]),
                       ["-memusage", "normal", "-gclim=64", "-drawthread=2"])
    }
}
