// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import PlayportKit

final class StorageCleanupTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default
    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("cleanup-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try fm.removeItem(at: root) }
    @discardableResult private func file(_ path: String, old: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 17).write(to: url)
        if old { try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: url.path) }
        return url
    }
    func testIdleClearsOnlyRebuildableFilesAndReportsActualRemovals() throws {
        for path in ["Library/Caches/dxmt/a", "Library/Caches/kosmickrisp/sub/b",
                     "Documents/prefix/drive_c/users/playport/AppData/Local/fex-emu/DiskCache/c"] { try file(path) }
        let cleaner = StorageCleanup(container: root!)
        XCTAssertEqual(cleaner.run(gameRunning: false).bytes, 51)
        let removed = cleaner.run(gameRunning: false, remove: true)
        XCTAssertEqual(removed.files, 3); XCTAssertEqual(removed.bytes, 51)
        XCTAssertEqual(cleaner.run(gameRunning: false).files, 0)
    }
    func testActivePlayPinsAllRuntimeCachesButCanClearOldReport() throws {
        let runtime = try file("Library/Caches/dxmt/pipeline")
        let old = try file("tmp/Report a problem/old.zip", old: true)
        let recent = try file("tmp/Report a problem/new.zip")
        let unrelated = try file("tmp/pairing-temp.plist", old: true)
        let result = StorageCleanup(container: root!).run(gameRunning: true, remove: true)
        XCTAssertEqual(result.files, 1)
        XCTAssertFalse(fm.fileExists(atPath: old.path))
        for path in [runtime, recent, unrelated] { XCTAssertTrue(fm.fileExists(atPath: path.path)) }
    }
    func testSavesOriginalsConfigurationAndOtherCachesAreNeverCandidates() throws {
        let paths = ["Documents/prefix/drive_c/Games/game.exe.orig", "Documents/Cloud Backups/old.zip",
                     "Documents/prefix/drive_c/Games/save.dat", "Library/Caches/Playport/art/cover.jpg",
                     "Documents/prefix/drive_c/users/playport/AppData/Local/fex-emu/Config.json",
                     "tmp/Report a problem/save.dat"]
        for p in paths { try file(p, old: true) }
        XCTAssertEqual(StorageCleanup(container: root!).run(gameRunning: false, remove: true).files, 0)
        for p in paths { XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent(p).path)) }
    }
    func testRejectsSymbolicCacheRootsAndNestedLinks() throws {
        let saved = try file("Documents/private/save.dat")
        let cache = root.appendingPathComponent("Library/Caches")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: cache.appendingPathComponent("dxmt"), withDestinationURL: saved.deletingLastPathComponent())
        let actual = try file("Library/Caches/kosmickrisp/real")
        try fm.createSymbolicLink(at: actual.deletingLastPathComponent().appendingPathComponent("linked"),
                                 withDestinationURL: saved.deletingLastPathComponent())
        XCTAssertEqual(StorageCleanup(container: root!).run(gameRunning: false, remove: true).files, 1)
        XCTAssertTrue(fm.fileExists(atPath: saved.path))
    }
    func testPreviewNeverMutatesAndScanIsBounded() throws {
        let p = try file("Library/Caches/dxmt/a")
        let cleaner = StorageCleanup(container: root!)
        XCTAssertEqual(cleaner.run(gameRunning: false).files, 1)
        XCTAssertTrue(fm.fileExists(atPath: p.path))
        XCTAssertTrue(cleaner.run(gameRunning: false, remove: true, fileLimit: 0).limited)
        XCTAssertTrue(fm.fileExists(atPath: p.path))
    }
}
