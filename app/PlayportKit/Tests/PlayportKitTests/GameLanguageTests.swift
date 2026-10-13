// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import PlayportKit

final class GameLanguageTests: XCTestCase {
    func testTraditionalChineseRegionsAndScript() {
        for locale in ["zh-TW", "zh-Hant", "zh-HK", "zh_MO"] {
            XCTAssertEqual(GameLanguage.suggested([locale]), .tchinese)
        }
    }

    func testSimplifiedJapaneseAndEnglishFallback() {
        XCTAssertEqual(GameLanguage.suggested(["zh-Hans-CN"]), .schinese)
        XCTAssertEqual(GameLanguage.suggested(["zh-Hans-TW"]), .schinese)
        XCTAssertEqual(GameLanguage.suggested(["zh-Hant-CN"]), .tchinese)
        XCTAssertEqual(GameLanguage.suggested(["ja-JP"]), .japanese)
        XCTAssertEqual(GameLanguage.suggested(["en-US", "zh-Hant"]), .english)
        XCTAssertEqual(GameLanguage.suggested([]), .english)
    }
}
