// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import PlayportKit

final class LaunchDiagnosticsTests: XCTestCase {
    func testZeroExitBeforeFrameIsVisibleButNormalPlayIsNot() {
        XCTAssertTrue(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0, drewFrame: false, elapsed: 1))
        XCTAssertTrue(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0xc0000005, drewFrame: false, elapsed: 1))
        XCTAssertFalse(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0, drewFrame: true, elapsed: 1))
        XCTAssertFalse(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0, drewFrame: false, elapsed: 60))
        XCTAssertFalse(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0, drewFrame: false, elapsed: .nan))
        XCTAssertEqual(LaunchProgress.failedStage("launch=failed steamapi=preparation"), .preparing)
    }

    func testNestedEngineLogsWithDuplicateNamesAndChineseInventory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["savedata", "logs"] {
            let dir = root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("引擎錯誤".utf8).write(to: dir.appendingPathComponent("krkr.console.log"))
        }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("中文.xp3"))
        try Data([4]).write(to: root.appendingPathComponent("credentials.ini"))
        XCTAssertEqual(LaunchDiagnostics.gameLogs(in: root).count, 2)
        XCTAssertTrue(LaunchDiagnostics.inventory(in: root).contains("3\t中文.xp3"))
        XCTAssertFalse(LaunchDiagnostics.inventory(in: root).contains(root.path))
    }

    func testWindowsDialogIsRestrictedToCurrentLaunch() throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: log) }
        let old = Data("002c:trace:msgbox:MessageBoxTimeoutW L\"old\"\n".utf8)
        try old.write(to: log)
        XCTAssertNil(LaunchDiagnostics.windowsMessage(in: log, after: UInt64(old.count)))
        let file = try FileHandle(forWritingTo: log)
        try file.seekToEnd()
        try file.write(contentsOf: Data("\0noise\n002c:trace:msgbox:MessageBoxTimeoutW L\"Cannot open data.xp3\"\n".utf8))
        try file.close()
        XCTAssertEqual(LaunchDiagnostics.windowsMessage(in: log, after: UInt64(old.count)), "L\"Cannot open data.xp3\"")
    }

    func testPatchedWineMessageBoxRevealsFatalError() {
        let english = #"002c:err:dialog:MessageBoxIndirectW [msgbox] style 0 caption L"Fatal Error" text L"Cannot convert given narrow string to wide string""#
        XCTAssertEqual(LaunchDiagnostics.lastWindowsMessage(in: english),
                       "Cannot convert given narrow string to wide string")
        let japanese = #"002c:err:dialog:MessageBoxIndirectW [msgbox] style 0 caption L"\81f4" text L"\6587\5b57\5217\3092 UNICODE \6587\5b57\5217\306b\5909\63db\3067\304d\307e\305b\3093""#
        XCTAssertEqual(LaunchDiagnostics.lastWindowsMessage(in: japanese),
                       "文字列を UNICODE 文字列に変換できません")
    }

    func testSenrenMetadataProbesDistinguishMissingFromPresent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertTrue(LaunchDiagnostics.inventory(in: root, steamAppID: 1144400)
            .contains("data.xp3\tmissing or unreadable"))
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("data.xp3"))
        XCTAssertTrue(LaunchDiagnostics.inventory(in: root, steamAppID: 1144400)
            .contains("data.xp3\tfile\t3 bytes"))
    }

    func testExternalSymlinksAndOversizeLogsExcluded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside.log"), withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
        try Data(repeating: 1, count: (2 << 20) + 1).write(to: root.appendingPathComponent("large.log"))
        XCTAssertTrue(LaunchDiagnostics.gameLogs(in: root).isEmpty)
        XCTAssertFalse(LaunchDiagnostics.inventory(in: root).contains("outside.log"))
    }
}
