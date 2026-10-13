// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import PlayportKit

final class KirikiriProbeTests: XCTestCase {
    private func directory(_ work: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kirikiri-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try work(root)
    }

    private func archive(_ name: String, at root: URL, good: Bool = true) throws {
        try Data(good ? KirikiriProbe.signature + [0,1,2] : Array("not an xp3".utf8))
            .write(to: root.appendingPathComponent(name))
    }

    func testDetectSteamKirikiriContentWithoutReadingEntireFiles() throws {
        try directory { root in
            try archive("DATA.XP3", at: root)
            try archive("patch.xp3", at: root)
            try "game".write(to: root.appendingPathComponent("startup.tjs"), atomically: true, encoding: .utf8)
            let d = try XCTUnwrap(KirikiriProbe.inspect(directory: root))
            XCTAssertEqual(d.entryArchive, "DATA.XP3")
            XCTAssertEqual(d.archives.count, 2)
            XCTAssertTrue(d.hasLooseStartupScript)
        }
    }

    func testRejectPretendXP3AndPatchOnly() throws {
        try directory { root in
            try archive("data.xp3", at: root, good: false)
            try archive("patch.xp3", at: root)
            XCTAssertNil(KirikiriProbe.inspect(directory: root))
        }
    }

    func testSelectMainArchiveWhenDataXP3Missing() throws {
        try directory { root in
            try archive("Game.XP3", at: root)
            try archive("patch2.xp3", at: root)
            let d = try XCTUnwrap(KirikiriProbe.inspect(directory: root))
            XCTAssertEqual(d.entryArchive, "Game.XP3")
            XCTAssertFalse(d.hasLooseStartupScript)
        }
    }

    func testRejectOutsideRootSymbolicLink() throws {
        try directory { root in
            let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).xp3")
            defer { try? FileManager.default.removeItem(at: outside) }
            try Data(KirikiriProbe.signature).write(to: outside)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("data.xp3"), withDestinationURL: outside)
            XCTAssertNil(KirikiriProbe.inspect(directory: root))
        }
    }
}
