// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import PlayportKit

final class LaunchDiagnosticsTests: XCTestCase {
    func testSaveAuditCoversBothBackendsWhenSlotsExceedTheOldEightMiBBudget() throws {
        let fm = FileManager.default, root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let roaming = root.appendingPathComponent("drive_c/users/playport/AppData/Roaming")
        let dirs = [roaming.appendingPathComponent("GSE Saves/1144400/remote"), roaming.appendingPathComponent("YuzuSoft/SenrenBanka")]
        let slot = Data(repeating: 0x71, count: 210_000)
        for dir in dirs {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for n in 0..<22 { try slot.write(to: dir.appendingPathComponent(String(format: "data_%04d.bmp", n))) }
        }
        let report = LaunchDiagnostics.senrenSaveState(prefix: root, gameRoot: root)
        XCTAssertTrue(report.contains("native/data_0021.bmp\t210000\t"))
        XCTAssertTrue(report.contains("steam: 22 file(s) audited")); XCTAssertTrue(report.contains("native: 22 file(s) audited"))
    }
    func testEngineTimingAuditDecodesOnlyAllowedScalarOptions() throws {
        let fm = FileManager.default, root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let native = root.appendingPathComponent("drive_c/users/playport/AppData/Roaming/YuzuSoft/SenrenBanka")
        try fm.createDirectory(at: native, withIntermediateDirectories: true)
        let config = #"contfreq="\x33\x30""# + "\n" + #"timerprec="high""# + "\n" + #"account="private secret""# + "\n" + #"vsync="C:\private""#
        try config.data(using: .utf16)!.write(to: native.appendingPathComponent("SenrenBanka.cfu"))
        let report = LaunchDiagnostics.senrenSaveState(prefix: root, gameRoot: root)
        XCTAssertTrue(report.contains("native/contfreq=30\n")); XCTAssertTrue(report.contains("native/timerprec=high\n"))
        XCTAssertFalse(report.contains("private")); XCTAssertFalse(report.contains("account=")); XCTAssertFalse(report.contains(root.path))
    }
    func testSaveAuditShowsBackendMismatchWithoutContentsOrCredentials() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let roaming = root.appendingPathComponent("drive_c/users/playport/AppData/Roaming")
        let api = roaming.appendingPathComponent("GSE Saves/1144400/remote")
        let native = roaming.appendingPathComponent("YuzuSoft/SenrenBanka")
        for dir in [api, native] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        try Data("Steam save contents".utf8).write(to: api.appendingPathComponent("datasu.ksd"))
        try Data("Different native contents".utf8).write(to: native.appendingPathComponent("DATASU.KSD"))
        try Data("account secret".utf8).write(to: api.appendingPathComponent("credentials.ini"))
        try fm.createSymbolicLink(at: api.appendingPathComponent("datasc.ksd"), withDestinationURL: api.appendingPathComponent("credentials.ini"))
        let report = LaunchDiagnostics.senrenSaveState(prefix: root, gameRoot: root)
        XCTAssertTrue(report.contains("steam/datasu.ksd\t19\t"))
        XCTAssertTrue(report.contains("native/datasu.ksd\t25\t"))
        for secret in [root.path, "Steam save contents", "Different native contents", "account secret", "credentials.ini", "datasc.ksd"] {
            XCTAssertFalse(report.contains(secret))
        }
    }
    func testCompatibilityHashesExcludeLinksSavesAndAccountFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: root.appendingPathComponent("SenrenBanka.exe"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("aarch64-windows"), withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: root.appendingPathComponent("aarch64-windows/xtajit.dll"))
        try Data("account-secret".utf8).write(to: root.appendingPathComponent("configs.user.ini"))
        try Data("private-save".utf8).write(to: root.appendingPathComponent("savedata.dat"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("SenrenBanka.cf"),
                                                 withDestinationURL: root.appendingPathComponent("configs.user.ini"))
        let text = LaunchDiagnostics.compatibilityFingerprints(gameRoot: root, runtime: root)
        XCTAssertTrue(text.contains("game/SenrenBanka.exe\t3\tba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
        XCTAssertTrue(text.contains("game/SenrenBanka.cf\tmissing, linked or over limit"))
        XCTAssertTrue(text.contains("runtime/aarch64/xtajit.dll\t3\tba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
        XCTAssertFalse(text.contains(root.path))
        XCTAssertFalse(text.contains("account-secret"))
        XCTAssertFalse(text.contains("private-save"))
        XCTAssertFalse(text.contains("configs.user.ini"))
    }

    func testZeroExitBeforeFrameIsVisibleButNormalPlayIsNot() {
        XCTAssertTrue(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0, drewFrame: false, elapsed: 1))
        XCTAssertTrue(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0xc0000005, drewFrame: false, elapsed: 1))
        XCTAssertFalse(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0, drewFrame: true, elapsed: 1))
        XCTAssertFalse(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0, drewFrame: false, elapsed: 60))
        XCTAssertTrue(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0, drewFrame: false, elapsed: 29,
                                                          windowsMessage: "Access Violation"))
        XCTAssertTrue(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0, drewFrame: false, elapsed: 60,
                                                          windowsMessage: "Access Violation"))
        XCTAssertFalse(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0, drewFrame: false, elapsed: 61,
                                                           windowsMessage: "message from a long session"))
        XCTAssertFalse(LaunchDiagnostics.endedBeforeDrawing(exitCode: 0, drewFrame: true, elapsed: 29,
                                                           windowsMessage: "message after drawing"))
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

    func testSteamMetadataChecksArchitectureWithoutReadingSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var pe = Data(repeating: 0, count: 256)
        pe[0] = 0x4d; pe[1] = 0x5a; pe[60] = 0x80
        pe[128] = 0x50; pe[129] = 0x45; pe[132] = 0x4c; pe[133] = 1
        try pe.write(to: root.appendingPathComponent("steam_api.dll"))
        try Data("private ticket should not appear".utf8).write(to: root.appendingPathComponent("configs.user.ini"))
        let report = LaunchDiagnostics.steamFiles(in: root)
        XCTAssertTrue(report.contains("machine=0x014C"))
        XCTAssertTrue(report.contains("initialization not yet observed"))
        XCTAssertFalse(report.contains("private ticket"))
        XCTAssertFalse(report.contains(root.path))
    }

    func testCodepageProbeIdentifiesActualTableAndMissingWindowsLink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let nls = root.appendingPathComponent("nls")
        try FileManager.default.createDirectory(at: nls, withIntermediateDirectories: true)
        try Data([13, 0, 0x10, 0x27, 1, 0]).write(to: nls.appendingPathComponent("c_10000.nls"))
        let report = LaunchDiagnostics.codepageFiles(prefix: root.appendingPathComponent("prefix"), runtime: root)
        XCTAssertTrue(report.contains("bundle/c_10000.nls\ttable=10000"))
        XCTAssertTrue(report.contains("system32/c_10000.nls\tmissing or unreadable"))
        XCTAssertFalse(report.contains(root.path))
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
