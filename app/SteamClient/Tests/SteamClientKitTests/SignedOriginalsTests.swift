// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import SteamClientKit

final class SignedOriginalsTests: XCTestCase {
    func testManyLongNamesFitTheTitleEnvironmentTransport() throws {
        let root = try scratchDir("signed-budget")
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("zMain.exe")
        let names = ["zMain.exe"] + (0..<31).map { String(repeating: "g", count: 180) + "\($0).exe" }
        for name in names {
            for suffix in ["", ".orig", ".sig"] { try Data([1]).write(to: root.appendingPathComponent(name + suffix)) }
        }
        let paths = SignedOriginals.paths(in: root, selectedExecutable: selected,
                                           windowsExecutable: "C:\\Games\\多語言遊戲資料夾\\zMain.exe")
        XCTAssertFalse(paths.isEmpty)
        XCTAssertEqual(paths.first, "C:\\Games\\多語言遊戲資料夾\\zMain.exe")
        XCTAssertLessThan(paths.count, names.count)
        XCTAssertLessThan(SignedOriginals.environmentKey.utf8.count + 1 + paths.joined(separator: "\n").utf8.count, 4096)
        XCTAssertTrue(paths.allSatisfy { $0.hasSuffix(".exe") })
    }

    func testOnlySignedTransformedFilesAreListedAndUnchanged() throws {
        let root = try scratchDir("signed-originals")
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtures = ["Game.exe", "Game.exe.orig", "Game.exe.sig", "unsigned.exe", "unsigned.exe.orig",
                        "untouched.exe", "untouched.exe.sig", "steam_api.dll", "steam_api.dll.orig", "steam_api.dll.sig",
                        "save.dat", "save.dat.orig", "save.dat.sig"]
        for name in fixtures { try Data(name.utf8).write(to: root.appendingPathComponent(name)) }
        XCTAssertEqual(SignedOriginals.paths(in: root, selectedExecutable: root.appendingPathComponent("Game.exe"),
                                             windowsExecutable: "C:\\Games\\測試 Game\\Game.exe"),
                       ["C:\\Games\\測試 Game\\Game.exe", "C:\\Games\\測試 Game\\steam_api.dll"])
        for name in fixtures { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name)), Data(name.utf8)) }
        XCTAssertTrue(SignedOriginals.paths(in: root, selectedExecutable: root.appendingPathComponent("Game.exe"),
                                             windowsExecutable: "C:\\Games\\Different.exe").isEmpty)
        XCTAssertTrue(SignedOriginals.paths(in: root, selectedExecutable: root.deletingLastPathComponent().appendingPathComponent("other.exe"),
                                             windowsExecutable: "C:\\Games\\other.exe").isEmpty)
    }

    func testNestedPathsAndSymlinkExclusion() throws {
        let root = try scratchDir("signed-links")
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["Game.exe", "Game.exe.orig", "Game.exe.sig"] { try Data([1]).write(to: bin.appendingPathComponent(name)) }
        let selected = bin.appendingPathComponent("Game.exe")
        XCTAssertEqual(SignedOriginals.paths(in: root, selectedExecutable: selected, windowsExecutable: "C:\\Games\\Title\\bin\\Game.exe"),
                       ["C:\\Games\\Title\\bin\\Game.exe"])
        try FileManager.default.removeItem(at: bin.appendingPathComponent("Game.exe.orig"))
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("Game.exe.orig"), withDestinationURL: selected)
        XCTAssertTrue(SignedOriginals.paths(in: root, selectedExecutable: selected, windowsExecutable: "C:\\Games\\Title\\bin\\Game.exe").isEmpty)
    }
}
