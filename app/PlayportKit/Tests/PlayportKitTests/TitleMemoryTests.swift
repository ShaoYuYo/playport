// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import PlayportKit

final class TitleMemoryTests: XCTestCase {
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
    func testEngineCadenceFollowsTheLaunchLimitWithoutOverridingExplicitArguments() {
        let p = TitleMemory(steamAppID: 1144400, i386: true, enabled: true)
        for fps in [0, 30, 60, 120] {
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

}
