// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import PlayportKit

final class TitleMemoryTests: XCTestCase {
    func testWarmupPrioritizesImportedExecutableAndReadsItOnlyOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4).write(to: root.appendingPathComponent("a.dll"))
        try Data(repeating: 2, count: 100).write(to: root.appendingPathComponent("z.exe"))
        let first = TitleAssetWarmup.run(in: root, executable: "z.exe", byteLimit: 50, seconds: 5)
        XCTAssertEqual(first.files, 1)
        XCTAssertEqual(first.bytes, 50)
        let all = TitleAssetWarmup.run(in: root, executable: "z.exe", seconds: 5)
        XCTAssertEqual(all.files, 2)
        XCTAssertEqual(all.bytes, 104)
    }

    func testWarmupSupportsOtherEnginesWithoutReadingWholeArchivesOrSaves() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["data.pak", "data.rpa", "data.arc", "data.vfs", "progress.sav", "steam_autocloud.vdf"] {
            try Data(repeating: 1, count: 1 << 20).write(to: root.appendingPathComponent(name))
        }
        let result = TitleAssetWarmup.run(in: root, seconds: 5)
        XCTAssertEqual(result.files, 4)
        XCTAssertEqual(result.bytes, 4 * (16 << 10))
    }

    func testWarmupRejectsLinkedPluginDirectoryAndTraversalExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        defer { try? fm.removeItem(at: root) }
        let game = root.appendingPathComponent("game"), outside = root.appendingPathComponent("other")
        try fm.createDirectory(at: game, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: outside.appendingPathComponent("private.dll"))
        try fm.createSymbolicLink(at: game.appendingPathComponent("plugin"), withDestinationURL: outside)
        let result = TitleAssetWarmup.run(in: game, executable: "../other/private.dll", seconds: 5)
        XCTAssertEqual(result.files, 0)
        XCTAssertEqual(result.bytes, 0)
    }

    func testWarmupHandlesMissingOrNonDirectoryInstallWithoutFailingLaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(TitleAssetWarmup.run(in: root).bytes, 0)
        try Data([1]).write(to: root)
        XCTAssertEqual(TitleAssetWarmup.run(in: root).files, 0)
    }

    func testWarmupBoundsBytesAndSkipsLinksAndPrivateFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 600_000).write(to: root.appendingPathComponent("a.dll"))
        try Data(repeating: 2, count: 600_000).write(to: root.appendingPathComponent("b.exe"))
        try Data(repeating: 3, count: 600_000).write(to: root.appendingPathComponent("private.ksd"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("c.dll"), withDestinationURL: root.appendingPathComponent("private.ksd"))
        let capped = TitleAssetWarmup.run(in: root, byteLimit: 700_000, seconds: 5)
        XCTAssertEqual(capped.files, 2); XCTAssertEqual(capped.bytes, 700_000)
        let all = TitleAssetWarmup.run(in: root, seconds: 5)
        XCTAssertEqual(all.files, 2); XCTAssertEqual(all.bytes, 2 * (512 << 10))
        XCTAssertEqual(TitleAssetWarmup.run(in: root, byteLimit: 0).bytes, 0)
        XCTAssertEqual(TitleAssetWarmup.run(in: root, seconds: 0).files, 0)
    }

    func testWarmupReadsBoundedXP3IndexAndRejectsOutOfFileOffsets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var data = Data([0x58,0x50,0x33,0x0d,0x0a,0x20,0x0a,0x1a,0x8b,0x67,0x01])
        data += Data([0,0,1,0,0,0,0,0]) // index at 64 KiB
        data += Data(repeating: 0, count: 1_000_000 - data.count)
        try data.write(to: root.appendingPathComponent("data.xp3"))
        XCTAssertEqual(TitleAssetWarmup.run(in: root, seconds: 5).bytes, (16 + 128) << 10)
        data.replaceSubrange(11..<19, with: repeatElement(UInt8(255), count: 8))
        try data.write(to: root.appendingPathComponent("data.xp3"))
        XCTAssertEqual(TitleAssetWarmup.run(in: root, seconds: 5).bytes, 16 << 10)
    }
    func testScopedBudgetAndOptOut() {
        let profile = TitleMemory(steamAppID: 1144400, i386: true, enabled: true)
        XCTAssertTrue(profile.active)
        XCTAssertEqual(profile.poolMB, 256)
        XCTAssertGreaterThan(profile.poolMB!, 26 + 128 + 100)
        for other in [TitleMemory(steamAppID: nil, i386: true, enabled: true),
                      TitleMemory(steamAppID: 367520, i386: true, enabled: true),
                      TitleMemory(steamAppID: 1144400, i386: false, enabled: true)] {
            XCTAssertTrue(other.active)
            XCTAssertFalse(other.engineProfile)
            XCTAssertNil(other.poolMB)
            XCTAssertEqual(other.config(over: ["jumbo-mb": "0"]), ["jumbo-mb": "0", "cpu-count": "2"])
            XCTAssertEqual(other.arguments(over: ["-custom"]), ["-custom"])
        }
    }

    func testGlobalOptOutAndSecondEngineBudget() {
        for app in [nil, 1144400, 2458530, 367520] as [UInt32?] {
            let off = TitleMemory(steamAppID: app, i386: true, enabled: false)
            XCTAssertFalse(off.active)
            XCTAssertNil(off.poolMB)
            XCTAssertEqual(off.config(over: [:]), [:])
            XCTAssertEqual(off.arguments(over: []), [])
        }
        let witch = TitleMemory(steamAppID: 2458530, i386: true, enabled: true)
        XCTAssertTrue(witch.engineProfile)
        XCTAssertEqual(witch.poolMB, 256)
        XCTAssertGreaterThan(witch.poolMB!, 26 + 161 + 64)
        XCTAssertTrue(witch.arguments(over: [], frameLimit: 60).contains("-gclim=64"))
    }

    func testRiddleJokerUsesMeasuredKirikiriProfileAndCanOptOut() {
        let profile = TitleMemory(steamAppID: 1277930, i386: true, enabled: true)
        XCTAssertTrue(profile.engineProfile)
        XCTAssertEqual(profile.poolMB, 256)
        XCTAssertGreaterThan(profile.poolMB!, 26 + 161 + 64)
        let args = profile.arguments(over: [], frameLimit: 60, displayRefreshRate: 60)
        for option in ["-memusage=normal", "-gclim=64", "-drawthread=2", "-contfreq=60"] {
            XCTAssertTrue(args.contains(option))
        }
        let explicit = ["-drawthread=1", "-memusage=low", "-contfreq=30", "-gclim=32"]
        XCTAssertEqual(profile.arguments(over: explicit, frameLimit: 60), explicit)
        let disabled = TitleMemory(steamAppID: 1277930, i386: true, enabled: false)
        XCTAssertNil(disabled.poolMB)
        XCTAssertEqual(disabled.arguments(over: []), [])
        XCTAssertEqual(disabled.config(over: [:]), [:])
        XCTAssertFalse(TitleMemory(steamAppID: 1277930, i386: false, enabled: true).engineProfile)
    }

    func testD3D9HasOnePresentationLimiterAndPreservesOverrides() {
        let base = ["DXVK_CONFIG": "dxvk.tilerMode = False;d3d9.presentInterval = 2", "OTHER": "kept"]
        for id: UInt32 in [1144400, 2458530, 1277930] {
            let profile = TitleMemory(steamAppID: id, i386: true, enabled: true)
            let result = profile.d3d9PresentationEnvironment(over: base)
            XCTAssertEqual(result["DXVK_CONFIG"], "d3d9.presentInterval = 0;d3d9.maxFrameRate = -1;" + base["DXVK_CONFIG"]!)
            XCTAssertEqual(result["OTHER"], "kept")
            XCTAssertEqual(profile.d3d9PresentationEnvironment(over: [:])["DXVK_CONFIG"], "d3d9.presentInterval = 0;d3d9.maxFrameRate = -1")
        }
        for profile in [TitleMemory(steamAppID: 1277930, i386: true, enabled: false),
                        TitleMemory(steamAppID: 1277930, i386: false, enabled: true),
                        TitleMemory(steamAppID: 42, i386: true, enabled: true)] {
            XCTAssertEqual(profile.d3d9PresentationEnvironment(over: base), base)
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
    func testEngineCadenceFollowsTheLaunchLimitWithoutOverridingExplicitArguments() {
        let p = TitleMemory(steamAppID: 1144400, i386: true, enabled: true)
        for fps in [30, 60, 120] {
            XCTAssertTrue(p.arguments(over: [], frameLimit: fps).contains("-contfreq=\(fps)"))
        }
        XCTAssertFalse(p.arguments(over: [], frameLimit: -1).contains { $0.hasPrefix("-contfreq") })
        for explicit in [["-CONTFREQ=30"], ["-contfreq", "0"]] {
            let args = p.arguments(over: explicit, frameLimit: 60)
            XCTAssertEqual(Array(args.prefix(explicit.count)), explicit)
            XCTAssertEqual(args.filter { $0.lowercased().hasPrefix("-contfreq") }.count, 1)
        }
        let other = TitleMemory(steamAppID: 1, i386: true, enabled: true)
        XCTAssertEqual(other.arguments(over: [], frameLimit: 60), [])
    }

    func testThirtyFPSLaunchDoesNotFreezeEngineBelowLaterPresentationChoice() {
        let p = TitleMemory(steamAppID: 1144400, i386: true, enabled: true)
        XCTAssertTrue(p.arguments(over: [], frameLimit: 30, displayRefreshRate: 60).contains("-contfreq=60"))
        XCTAssertTrue(p.arguments(over: [], frameLimit: 30, displayRefreshRate: 120).contains("-contfreq=120"))
        XCTAssertTrue(p.arguments(over: [], frameLimit: 0, displayRefreshRate: 120).contains("-contfreq=120"))
        let explicit = p.arguments(over: ["-CONTFREQ=30"], frameLimit: 60, displayRefreshRate: 120)
        XCTAssertEqual(explicit.filter { $0.lowercased().hasPrefix("-contfreq") }, ["-CONTFREQ=30"])
    }

    func testUnlimitedPresentationNeverDefaultsToUnboundedContinuousWork() {
        let p = TitleMemory(steamAppID: 1144400, i386: true, enabled: true)
        for panel in [nil, 0, -1, 60] as [Int?] {
            XCTAssertTrue(p.arguments(over: [], frameLimit: 0, displayRefreshRate: panel).contains("-contfreq=60"))
        }
        XCTAssertTrue(p.arguments(over: [], frameLimit: 240, displayRefreshRate: 60).contains("-contfreq=60"))
        XCTAssertTrue(p.arguments(over: [], frameLimit: 0, displayRefreshRate: 1000).contains("-contfreq=240"))
        for explicit in [["-CONTFREQ=0"], ["-contfreq", "0"]] {
            let args = p.arguments(over: explicit, frameLimit: 0, displayRefreshRate: 60)
            XCTAssertEqual(Array(args.prefix(explicit.count)), explicit)
            XCTAssertEqual(args.filter { $0.lowercased().hasPrefix("-contfreq") }.count, 1)
        }
    }

}
