// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import SteamClientKit

/// A PICS record with Hollow Knight-like save rules (made up).
func cloudApp() throws -> KeyValue {
    try KeyValue.parseText(Array("""
    "367520"
    {
        "common" { "name" "Knight" }
        "ufs"
        {
            "quota" "1000000"
            "savefiles"
            {
                "0" { "root" "WinAppDataLocalLow" "path" "Team Cherry/Hollow Knight" "pattern" "user*.dat" }
                "1" { "root" "WinMyDocuments" "path" "Knight/{64BitSteamID}" "pattern" "*" "recursive" "1" }
                "2" { "root" "MacAppSupport" "path" "x" "pattern" "*" "platforms" { "1" "MacOS" } }
            }
        }
    }
    """.utf8))
}

/// A PICS record with Portal 2's save rule as it spells it: the root in lower
/// case, while Steam lists the files a Windows client uploaded as `%GameInstall%`.
func portal2CloudApp() throws -> KeyValue {
    try KeyValue.parseText(Array("""
    "620"
    {
        "common" { "name" "Portal 2" }
        "ufs"
        {
            "savefiles"
            {
                "0" { "root" "gameinstall" "path" "portal2/SAVE/{64BitSteamID}/" "pattern" "*.sav" }
            }
        }
    }
    """.utf8))
}

final class CloudTests: XCTestCase {
    var dir: URL!
    var roots: Cloud.Roots!

    override func setUpWithError() throws {
        dir = try scratchDir("cloud")
        roots = Cloud.Roots(user: dir.appendingPathComponent("users/playport"), gameInstall: dir.appendingPathComponent("Games/Knight"),
                            remote: dir.appendingPathComponent("GSE Saves/367520/remote"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func write(_ url: URL, _ text: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testRootsMapIntoThePrefixAndMatchCaseAsWindowsDoes() throws {
        XCTAssertEqual(roots.file("%WinAppDataLocalLow%Team Cherry/Hollow Knight/user1.dat")?.path,
                       dir.appendingPathComponent("users/playport/AppData/LocalLow/Team Cherry/Hollow Knight/user1.dat").path)
        XCTAssertEqual(roots.file("save.bin")?.path, dir.appendingPathComponent("GSE Saves/367520/remote/save.bin").path,
                       "no token: the emulator's remote storage")
        XCTAssertEqual(roots.file("%GameInstall%saves/a.sav")?.path, dir.appendingPathComponent("Games/Knight/saves/a.sav").path)
        XCTAssertNil(roots.file("%LinuxHome%x"), "a root Playport does not map")
        XCTAssertNil(roots.file("%WinMyDocuments%../escape"))
        try write(dir.appendingPathComponent("users/playport/AppData/LocalLow/TEAM CHERRY/x.dat"), "a")
        XCTAssertEqual(roots.file("%WinAppDataLocalLow%Team Cherry/x.dat")?.path,
                       dir.appendingPathComponent("users/playport/AppData/LocalLow/TEAM CHERRY/x.dat").path)
    }

    func testARulesRootTakesSteamsSpellingAndLocalNamesTakeSteamsCase() throws {
        let rules = Cloud.rules(try portal2CloudApp())
        XCTAssertEqual(rules.map(\.root), ["gameinstall"])
        let save = dir.appendingPathComponent("Games/Knight/portal2/SAVE/42")
        try write(save.appendingPathComponent("autosave.sav"), "auto")
        try write(save.appendingPathComponent("1791103990.sav"), "quick")
        let files = Cloud.localFiles(rules: rules, roots: roots, steamID: 42)
        XCTAssertEqual(files.keys.sorted(), ["%GameInstall%portal2/SAVE/42/1791103990.sav", "%GameInstall%portal2/SAVE/42/autosave.sav"],
                       "the token as Steam lists it, not as the rule spells it")
        XCTAssertEqual(Cloud.canonicalRoot("WINAPPDATALOCALLOW"), "WinAppDataLocalLow")
        XCTAssertEqual(Cloud.canonicalRoot("LinuxHome"), "LinuxHome", "a root Playport does not map stays as given")

        // A file an earlier sync uploaded under the rule's spelling keeps the name Steam has for it.
        let named = Cloud.named(files, like: ["%gameinstall%portal2/SAVE/42/1791103990.sav", "%GameInstall%portal2/save/42/other.sav"])
        XCTAssertEqual(named.keys.sorted(), ["%GameInstall%portal2/SAVE/42/autosave.sav", "%gameinstall%portal2/SAVE/42/1791103990.sav"])
        XCTAssertEqual(named["%gameinstall%portal2/SAVE/42/1791103990.sav"], files["%GameInstall%portal2/SAVE/42/1791103990.sav"])
        let first = Cloud.named(["a/X.sav": save, "a/x.sav": dir], like: ["A/x.sav", "a/x.SAV"])
        XCTAssertEqual(first, ["A/x.sav": save], "the first of the names wins, and two local names for one file become one")
    }

    func testRulesAndTheLocalFilesTheyCover() throws {
        let rules = Cloud.rules(try cloudApp())
        XCTAssertEqual(rules.map(\.root), ["WinAppDataLocalLow", "WinMyDocuments"], "the macOS rule is skipped")
        let hk = dir.appendingPathComponent("users/playport/AppData/LocalLow/Team Cherry/Hollow Knight")
        try write(hk.appendingPathComponent("user1.dat"), "one")
        try write(hk.appendingPathComponent("shared.dat"), "not a user file")
        try write(hk.appendingPathComponent("sub/user2.dat"), "not recursive")
        try write(dir.appendingPathComponent("users/playport/Documents/Knight/42/slot/a.sav"), "recursive")
        try write(dir.appendingPathComponent("GSE Saves/367520/remote/api.bin"), "through the API")
        let files = Cloud.localFiles(rules: rules, roots: roots, steamID: 42)
        XCTAssertEqual(files.keys.sorted(), ["%WinAppDataLocalLow%Team Cherry/Hollow Knight/user1.dat",
                                             "%WinMyDocuments%Knight/42/slot/a.sav", "api.bin"])
        XCTAssertTrue(Cloud.glob("user*.dat", "USER3.DAT"))
        XCTAssertFalse(Cloud.glob("user?.dat", "user10.dat"))
    }

    func testThePlan() {
        func r(_ sha: String) -> Cloud.Remote { .init(name: "", sha: sha, size: 1, time: 0) }
        let base = Cloud.Baseline(changeNumber: 1, files: ["same": "a", "phone": "a", "steam": "a", "both": "a", "gone": "a"])
        let plan = Cloud.plan(remote: ["same": r("a"), "phone": r("a"), "steam": r("b"), "both": r("b"), "gone": r("a"), "newsteam": r("c")],
                              local: ["same": "a", "phone": "b", "steam": "a", "both": "c", "newphone": "d"], baseline: base)
        XCTAssertEqual(plan, ["phone": .upload, "steam": .download, "both": .conflict, "gone": .download, "newsteam": .download, "newphone": .upload],
                       "a missing local copy is restored without deleting Steam's save")
        let first = Cloud.plan(remote: ["x": r("a"), "y": r("b")], local: ["x": "a", "y": "c", "z": "d"], baseline: nil)
        XCTAssertEqual(first, ["y": .conflict], "no baseline: a difference is the player's to settle, a phone-only file waits")
    }

    func testABodyIsTakenAsIsOrUnzippedButAlwaysChecked() throws {
        let content = Array("the save".utf8)
        let sha = SHA1.hash(content).hex
        XCTAssertEqual(try Cloud.content(content, rawSize: 8, sha: sha), content)
        XCTAssertThrowsError(try Cloud.content(Array("tampered".utf8), rawSize: 8, sha: sha))
        XCTAssertThrowsError(try Cloud.content(Array("PK\u{3}\u{4}junk".utf8), rawSize: 8, sha: sha))
    }

    func testTheChangelistNamesFilesByPrefix() throws {
        var w = ProtoWriter()
        w.uint64(1, 9)
        for (name, prefix, state) in [("user1.dat", 0, 0), ("old.dat", 0, 2), ("api.bin", -1, 0)] as [(String, Int, UInt32)] {
            var m = ProtoWriter()
            m.string(1, name); m.bytes(2, SHA1.hash(Array(name.utf8))); m.uint64(3, 5); m.uint32(4, 3); m.uint32(5, state)
            if prefix >= 0 { m.uint32(7, UInt32(prefix)) }
            w.bytes(2, m.bytes)
        }
        w.string(4, "%WinAppDataLocalLow%Team Cherry/Hollow Knight/")
        let r = try CCloudGetAppFileChangelistResponse.decode(w.bytes)
        XCTAssertEqual(r.currentChangeNumber, 9)
        XCTAssertEqual(r.remote.keys.sorted(), ["%WinAppDataLocalLow%Team Cherry/Hollow Knight/user1.dat", "api.bin"],
                       "a deleted file is not listed")
    }
}

final class CloudServiceTests: XCTestCase {
    var dir: URL!
    var roots: Cloud.Roots!
    let saveName = "%WinAppDataLocalLow%Team Cherry/Hollow Knight/user1.dat"

    override func setUpWithError() throws {
        dir = try scratchDir("cloud-svc")
        roots = Cloud.Roots(user: dir.appendingPathComponent("users/playport"), gameInstall: dir.appendingPathComponent("Games/Knight"),
                            remote: dir.appendingPathComponent("GSE Saves/367520/remote"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    var save: URL { roots.file(saveName)! }
    var backups: URL { dir.appendingPathComponent("backups") }

    func service(_ b: FakeBackend) async throws -> SteamService {
        await b.set(library: [367520], [367520: try cloudApp()])
        await b.set(stored: FakeBackend.session(exp: 2_000_000_000))
        let s = SteamService(backend: b, log: .silent, stateDirectory: dir.appendingPathComponent("state"))
        _ = await s.restoreIfPossible()
        return s
    }

    func text(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }

    func testAFreshPhoneGetsSteamsSaveAndThenSendsItsPlays() async throws {
        let b = FakeBackend()
        await b.set(cloud: [saveName: Array("from the PC".utf8)])
        let s = try await service(b)
        let first = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(first.downloaded, [saveName])
        XCTAssertEqual(text(save), "from the PC")

        // A play changes the save: it goes up, once.
        try Data("played on the phone".utf8).write(to: save)
        let second = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(second.uploaded, [saveName])
        let onSteam = await b.cloudFile(saveName)
        XCTAssertEqual(onSteam, Array("played on the phone".utf8))
        let third = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(third.uploaded + third.downloaded, [])

        // The PC plays next: it comes down, and the phone's copy is backed up.
        await b.set(cloud: [saveName: Array("the PC again".utf8)])
        let fourth = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(fourth.downloaded, [saveName])
        XCTAssertEqual(text(save), "the PC again")
        let kept = TitleInstaller.regularFiles(under: backups)
        XCTAssertEqual(kept.count, 2)
        XCTAssertEqual(Set(kept.compactMap { text(backups.appendingPathComponent($0)) }),
                       Set(["from the PC", "played on the phone"]))
    }

    /// Portal 2: its rule spells the root `gameinstall`, Steam lists `%GameInstall%`. Each save
    /// had two names, and every sync sent Steam copies it refused (DuplicateRequest).
    func testPortal2sSavesSyncUnderTheNamesSteamHas() async throws {
        let auto = "%GameInstall%portal2/SAVE/7/autosave.sav"
        let earlier = "%gameinstall%portal2/SAVE/7/1791103990.sav"   // uploaded under the rule's spelling
        let config = "cfg/config.cfg"                                   // through ISteamRemoteStorage
        let b = FakeBackend()
        await b.set(cloud: [auto: Array("pc auto".utf8), earlier: Array("phone quick".utf8), config: Array("cfg".utf8)])
        await b.set(library: [620], [620: try portal2CloudApp()])
        await b.set(stored: FakeBackend.session(exp: 2_000_000_000))
        let s = SteamService(backend: b, log: .silent, stateDirectory: dir.appendingPathComponent("state"))
        _ = await s.restoreIfPossible()
        let p2 = Cloud.Roots(user: dir.appendingPathComponent("users/playport"), gameInstall: dir.appendingPathComponent("Games/Portal 2"),
                             remote: dir.appendingPathComponent("GSE Saves/620/remote"))

        let first = try await s.syncCloud(appID: 620, roots: p2, backups: backups)
        XCTAssertEqual(first.downloaded.sorted(), [auto, earlier, config].sorted())
        let saves = dir.appendingPathComponent("Games/Portal 2/portal2/SAVE/7")
        XCTAssertEqual(text(saves.appendingPathComponent("autosave.sav")), "pc auto")
        XCTAssertEqual(text(dir.appendingPathComponent("GSE Saves/620/remote/cfg/config.cfg")), "cfg")

        let unchanged = try await s.syncCloud(appID: 620, roots: p2, backups: backups)
        XCTAssertEqual(unchanged.uploaded + unchanged.downloaded, [], "no second name for a file Steam has")
        XCTAssertEqual(unchanged.failed, [:])
        XCTAssertEqual(unchanged.conflicts, [])

        // A play saves anew and rewrites the autosave: both go up, under Steam's spelling.
        try Data("phone auto".utf8).write(to: saves.appendingPathComponent("autosave.sav"))
        try Data("new save".utf8).write(to: saves.appendingPathComponent("1791200000.sav"))
        let played = try await s.syncCloud(appID: 620, roots: p2, backups: backups)
        XCTAssertEqual(played.uploaded, ["%GameInstall%portal2/SAVE/7/1791200000.sav", auto])
        XCTAssertEqual(played.failed, [:])
        let onSteam = await b.cloudFile(auto)
        XCTAssertEqual(onSteam, Array("phone auto".utf8))

        // The PC plays next: Steam's newer autosave comes down before the phone's next play.
        await b.set(cloud: [auto: Array("pc again".utf8), earlier: Array("phone quick".utf8), config: Array("cfg".utf8),
                            "%GameInstall%portal2/SAVE/7/1791200000.sav": Array("new save".utf8)])
        let next = try await s.syncCloud(appID: 620, roots: p2, backups: backups)
        XCTAssertEqual(next.downloaded, [auto])
        XCTAssertEqual(next.uploaded, [])
        XCTAssertEqual(text(saves.appendingPathComponent("autosave.sav")), "pc again")
    }

    func testBothChangedIsAConflictThePlayerSettles() async throws {
        let b = FakeBackend()
        await b.set(cloud: [saveName: Array("v1".utf8)])
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        try Data("phone v2".utf8).write(to: save)
        await b.set(cloud: [saveName: Array("pc v2".utf8)])
        let r = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(r.conflicts.map(\.name), [saveName])
        XCTAssertEqual(r.conflicts[0].phoneSize, 8)
        XCTAssertEqual(r.conflicts[0].steamSize, 5)
        XCTAssertEqual(text(save), "phone v2", "nothing moves until the player chooses")
        let kept = await s.keptCloud(appID: 367520)
        XCTAssertEqual(kept?.conflicts.map(\.name), [saveName])

        // Keep the phone's: it goes up, Steam's is backed up first.
        let settled = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, resolve: [saveName: .phone])
        XCTAssertEqual(settled.uploaded, [saveName])
        XCTAssertEqual(settled.conflicts, [])
        let onSteam = await b.cloudFile(saveName)
        XCTAssertEqual(onSteam, Array("phone v2".utf8))
        XCTAssertEqual(TitleInstaller.regularFiles(under: backups).map { text(backups.appendingPathComponent($0)) }, ["pc v2"])
    }

    func testKeepingSteamsCopyInAConflict() async throws {
        let b = FakeBackend()
        await b.set(cloud: [saveName: Array("steam".utf8)])
        try FileManager.default.createDirectory(at: save.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("phone".utf8).write(to: save)
        let s = try await service(b)
        let first = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(first.conflicts.map(\.name), [saveName], "a first sync never overwrites either side")
        let r = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, resolve: [saveName: .steam])
        XCTAssertEqual(r.downloaded, [saveName])
        XCTAssertEqual(text(save), "steam")
        XCTAssertEqual(TitleInstaller.regularFiles(under: backups).map { text(backups.appendingPathComponent($0)) }, ["phone"])
    }

    func testAFirstSyncAsksBeforeUploadingAPhoneOnlySave() async throws {
        let b = FakeBackend()
        let s = try await service(b)
        try FileManager.default.createDirectory(at: save.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("phone only".utf8).write(to: save)
        let first = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(first.uploaded, [])
        XCTAssertEqual(first.conflicts.map(\.name), [saveName])
        XCTAssertNil(first.conflicts[0].steamSize)
        // Unanswered, it stays a question: a later sync does not upload it.
        let unanswered = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(unanswered.uploaded, [])
        XCTAssertEqual(unanswered.conflicts.map(\.name), [saveName])
        // Kept off Steam by choice: it stays off, until the game changes it.
        let off = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, resolve: [saveName: .steam])
        XCTAssertEqual(off.uploaded + off.downloaded, [])
        XCTAssertEqual(off.conflicts, [])
        XCTAssertEqual(text(save), "phone only")
        try Data("played".utf8).write(to: save)
        let later = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(later.uploaded, [saveName])
    }

    func testOneChoiceSettlesEveryConflictInOneSyncAndKeepsTheOtherSide() async throws {
        let other = "%WinAppDataLocalLow%Team Cherry/Hollow Knight/user2.dat"
        let b = FakeBackend()
        await b.set(cloud: [saveName: Array("pc 1".utf8), other: Array("pc 2".utf8)])
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        try Data("phone 1".utf8).write(to: save)
        try Data("phone 2".utf8).write(to: roots.file(other)!)
        await b.set(cloud: [saveName: Array("pc 1b".utf8), other: Array("pc 2b".utf8)])
        let r = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(r.conflicts.map(\.name), [saveName, other])

        // Forgotten, the next sync is a first one: the same files are still the question.
        await s.forgetCloud(appID: 367520)
        let again = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(again.conflicts.map(\.name), [saveName, other])

        let resolve = SteamService.resolveAll(r.conflicts, .steam)
        XCTAssertEqual(resolve, [saveName: .steam, other: .steam])
        let settled = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, resolve: resolve)
        XCTAssertEqual(settled.conflicts, [])
        XCTAssertEqual(settled.downloaded.sorted(), [saveName, other])
        XCTAssertEqual(text(save), "pc 1b")
        // The phone's copies, the side not picked, are in one sync's backup folder.
        let kept = TitleInstaller.regularFiles(under: backups).sorted()
        XCTAssertEqual(kept.count, 2)
        XCTAssertEqual(Set(kept.map { $0.split(separator: "/").dropLast().joined(separator: "/") }).count, 1)
        XCTAssertEqual(Set(kept.compactMap { text(backups.appendingPathComponent($0)) }), ["phone 1", "phone 2"])
    }

    func testBackupsLastThirtyDays() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let day: TimeInterval = 24 * 3600
        let name = Cloud.Backups.folderName(for: now)
        XCTAssertFalse(name.contains(":"))
        XCTAssertEqual(Cloud.Backups.date(ofFolder: name), now)
        XCTAssertNil(Cloud.Backups.date(ofFolder: "notes"))

        let fm = FileManager.default
        func make(_ app: String, _ folder: String) throws -> URL {
            let url = backups.appendingPathComponent("\(app)/\(folder)", isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url.appendingPathComponent("user1.dat"))
            return url
        }
        let old = try make("367520", Cloud.Backups.folderName(for: now - 31 * day))
        let recent = try make("367520", Cloud.Backups.folderName(for: now - 29 * day))
        let lone = try make("292030", Cloud.Backups.folderName(for: now - 40 * day))
        XCTAssertEqual(Cloud.Backups.expired(in: backups, now: now).map(\.lastPathComponent).sorted(),
                       [old.lastPathComponent, lone.lastPathComponent].sorted())
        let removed = Cloud.Backups.prune(backups, now: now)
        XCTAssertEqual(removed.count, 2)
        XCTAssertFalse(fm.fileExists(atPath: old.path))
        XCTAssertTrue(fm.fileExists(atPath: recent.path))
        XCTAssertFalse(fm.fileExists(atPath: lone.deletingLastPathComponent().path), "a game's folder left empty goes too")
        XCTAssertEqual(Cloud.Backups.prune(backups, now: now), [])
        XCTAssertEqual(Cloud.Backups.prune(backups.appendingPathComponent("none"), now: now), [])
    }

    func testCloudSavesReachBothNativeAndRemoteStorageAndUploadEitherBackendsProgress() async throws {
        let b = FakeBackend(), name = "datasu.ksd"
        roots.gameSaveMirror = dir.appendingPathComponent("native")
        await b.set(cloud: [name: Array("PC progress".utf8)])
        let s = try await service(b)
        let r = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(r.downloaded, [name])
        XCTAssertEqual(text(roots.mirrorFile(name)!), "PC progress")
        XCTAssertEqual(text(roots.file(name)!), "PC progress")

        try Data("native play".utf8).write(to: roots.mirrorFile(name)!)
        let native = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(native.uploaded, [name])
        XCTAssertEqual(text(roots.file(name)!), "native play")
        try Data("remote play".utf8).write(to: roots.file(name)!)
        let api = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(api.uploaded, [name])
        XCTAssertEqual(text(roots.mirrorFile(name)!), "remote play")
        let upper = roots.gameSaveMirror!.appendingPathComponent("DATASU.KSD")
        try FileManager.default.moveItem(at: roots.mirrorFile(name)!, to: upper)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(roots.mirrorFile(name), upper)
        XCTAssertNil(roots.mirrorFile("data_anchor.ksd"))
        XCTAssertNil(roots.mirrorFile("krkr.console.log"))
        XCTAssertNil(roots.mirrorFile("../datasu.ksd"))
    }

    func testDivergentLocalBackendsAskAndKeepAllLosingCopies() async throws {
        let b = FakeBackend(), name = "datasu.ksd"
        roots.gameSaveMirror = dir.appendingPathComponent("native")
        await b.set(cloud: [name: Array("PC original".utf8)])
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        try Data("native new".utf8).write(to: roots.mirrorFile(name)!)
        try Data("remote new".utf8).write(to: roots.file(name)!)
        let conflict = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(conflict.conflicts.map(\.name), [name])
        XCTAssertEqual(conflict.conflicts.first?.localCopiesDiffer, true)
        XCTAssertEqual(text(roots.mirrorFile(name)!), "native new")
        XCTAssertEqual(text(roots.file(name)!), "remote new")
        let settled = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, resolve: [name: .steam])
        XCTAssertTrue(settled.failed.isEmpty)
        XCTAssertEqual(text(roots.mirrorFile(name)!), "PC original")
        XCTAssertEqual(text(roots.file(name)!), "PC original")
        let kept = TitleInstaller.regularFiles(under: backups).compactMap { text(backups.appendingPathComponent($0)) }
        XCTAssertTrue(kept.contains("native new"))
        XCTAssertTrue(kept.contains("remote new"))
    }

    func testMissingDownloadedSaveIsRestoredDespiteExistingBaseline() async throws {
        let b = FakeBackend()
        await b.set(cloud: [saveName: Array("PC".utf8)])
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        try FileManager.default.removeItem(at: save)
        let restored = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(restored.downloaded, [saveName])
        XCTAssertEqual(text(save), "PC")
    }

    func testAddingNativeBackendToAnOldBaselineCannotUploadFreshProgressOverPC() async throws {
        let b = FakeBackend(), name = "datasu.ksd"
        await b.set(cloud: [name: Array("existing PC progress".utf8)])
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        // Upgrade from the old remote-only mapping: this backend was never
        // part of its baseline, even though the canonical copy matched Steam.
        roots.gameSaveMirror = dir.appendingPathComponent("native")
        try FileManager.default.createDirectory(at: roots.gameSaveMirror!, withIntermediateDirectories: true)
        try Data("fresh game progress".utf8).write(to: roots.mirrorFile(name)!)
        let r = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(r.conflicts.map(\.name), [name])
        XCTAssertTrue(r.uploaded.isEmpty)
        let pc = await b.cloudFile(name)
        XCTAssertEqual(pc, Array("existing PC progress".utf8))
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, resolve: [name: .steam])
        XCTAssertEqual(text(roots.mirrorFile(name)!), "existing PC progress")
    }

    func testSignOutForgetsTheBaseline() async throws {
        let b = FakeBackend()
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state/steam-cloud").path))
        _ = try await s.signOut()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state/steam-cloud").path))
    }

    func testExplicitSteamRepairRefetchesAgreedFilesAndNeverUploadsLocalProgress() async throws {
        let b = FakeBackend(), name = "datasu.ksd"
        roots.gameSaveMirror = dir.appendingPathComponent("native")
        await b.set(cloud: [name: Array("PC original".utf8)])
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        try Data("phone changed".utf8).write(to: roots.file(name)!)
        try Data("native changed".utf8).write(to: roots.mirrorFile(name)!)
        let r = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, restoreSteam: true)
        XCTAssertEqual(r.downloaded, [name]); XCTAssertTrue(r.uploaded.isEmpty); XCTAssertTrue(r.conflicts.isEmpty)
        XCTAssertEqual(text(roots.file(name)!), "PC original")
        XCTAssertEqual(text(roots.mirrorFile(name)!), "PC original")
        let pc = await b.cloudFile(name); XCTAssertEqual(pc, Array("PC original".utf8))
        let versions = TitleInstaller.regularFiles(under: backups).compactMap { text(backups.appendingPathComponent($0)) }
        XCTAssertTrue(versions.contains("phone changed")); XCTAssertTrue(versions.contains("native changed"))
        let again = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, restoreSteam: true)
        XCTAssertEqual(again.downloaded, [name], "repair must re-fetch even when baseline already agrees")
    }

    func testOrdinaryUploadKeepsThePreviousSteamVersion() async throws {
        let b = FakeBackend()
        await b.set(cloud: [saveName: Array("PC original".utf8)])
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        try Data("phone new".utf8).write(to: save)
        let r = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertEqual(r.uploaded, [saveName])
        let kept = TitleInstaller.regularFiles(under: backups).compactMap { text(backups.appendingPathComponent($0)) }
        XCTAssertTrue(kept.contains("PC original"))
    }

    func testChangedDownloadDoesNotReplaceLocalSaveOrEstablishAgreement() async throws {
        let b = FakeBackend()
        await b.set(cloud: [saveName: Array("Steam original".utf8)])
        await b.replaceCloudDownload(Array("changed while downloading".utf8))
        try FileManager.default.createDirectory(at: save.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("phone original".utf8).write(to: save)
        let s = try await service(b)
        let r = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, restoreSteam: true)
        XCTAssertNotNil(r.failed[saveName]); XCTAssertTrue(r.uploaded.isEmpty); XCTAssertTrue(r.downloaded.isEmpty)
        XCTAssertEqual(text(save), "phone original")
        await b.replaceCloudDownload(nil)
        let retry = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, restoreSteam: true)
        XCTAssertEqual(retry.downloaded, [saveName]); XCTAssertEqual(text(save), "Steam original")
    }

    func testCloudAuditComparesObservedSteamBytesAndBothBackendsWithoutPayloads() async throws {
        let b = FakeBackend(), name = "datasu.ksd"
        await b.set(cloud: [name: Array("synthetic progress".utf8), "private-note.txt": Array("private text".utf8)])
        roots.gameSaveMirror = dir.appendingPathComponent("native")
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        let matched = await s.cloudSaveEvidence(appID: 367520, roots: roots)
        XCTAssertTrue(matched.contains("remote-local=matches native-local=matches"))
        XCTAssertFalse(matched.contains("synthetic progress"))
        XCTAssertFalse(matched.contains("private-note"))
        XCTAssertFalse(matched.contains(dir.path))
        try Data("changed after sync".utf8).write(to: roots.mirrorFile(name)!)
        let changed = await s.cloudSaveEvidence(appID: 367520, roots: roots)
        XCTAssertTrue(changed.contains("remote-local=matches native-local=differs"))
        try FileManager.default.removeItem(at: roots.mirrorFile(name)!)
        try FileManager.default.createSymbolicLink(at: roots.mirrorFile(name)!, withDestinationURL: roots.file(name)!)
        let linked = await s.cloudSaveEvidence(appID: 367520, roots: roots)
        // mirrorFile rejects links before the audit can read their bytes.
        XCTAssertTrue(linked.contains("native-local=unmapped"))
    }

    func testLegacyCloudRecordStillDecodesAndDoesNotInventRemoteEvidence() async throws {
        let b = FakeBackend()
        await b.set(cloud: ["datasu.ksd": Array("PC".utf8)])
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        let url = dir.appendingPathComponent("state/steam-cloud/367520.json")
        var old = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        old.removeValue(forKey: "remoteSnapshot")
        try JSONSerialization.data(withJSONObject: old).write(to: url)
        let kept = await s.keptCloud(appID: 367520)
        XCTAssertNotNil(kept)
        let report = await s.cloudSaveEvidence(appID: 367520, roots: roots)
        XCTAssertTrue(report.contains("snapshot: unavailable"))
    }

    func testForcedRestoreReplacesExistingSystemAndSlotFilesInBothBackends() async throws {
        let b = FakeBackend()
        let saved = ["datasu.ksd": "Steam system", "data_0010_01.bmp": "Steam slot", "savecheck": "Steam check"]
        await b.set(cloud: saved.mapValues { Array($0.utf8) })
        roots.gameSaveMirror = dir.appendingPathComponent("native")
        try FileManager.default.createDirectory(at: roots.remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: roots.gameSaveMirror!, withIntermediateDirectories: true)
        for name in saved.keys {
            try Data("old remote".utf8).write(to: roots.file(name)!)
            try Data("old native".utf8).write(to: roots.mirrorFile(name)!)
        }
        let s = try await service(b)
        let r = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, restoreSteam: true)
        XCTAssertTrue(r.failed.isEmpty); XCTAssertTrue(r.uploaded.isEmpty)
        for (name, expected) in saved {
            XCTAssertEqual(text(roots.file(name)!), expected)
            XCTAssertEqual(text(roots.mirrorFile(name)!), expected)
        }
        let kept = TitleInstaller.regularFiles(under: backups).compactMap { text(backups.appendingPathComponent($0)) }
        XCTAssertTrue(kept.contains("old remote")); XCTAssertTrue(kept.contains("old native"))
    }

    func testChoosingSteamForTheGameRestoresTheWholeSnapshotWithoutUploadingFreshSystemProgress() async throws {
        let b = FakeBackend()
        let original = ["datasu.ksd": "PC progress", "data_0010_01.bmp": "PC slot", "savecheck": "check"]
        await b.set(cloud: original.mapValues { Array($0.utf8) })
        roots.gameSaveMirror = dir.appendingPathComponent("native")
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        // System progress changed only locally; the slot changed on both sides.
        // Choosing Steam for the game must not upload that fresh system file.
        try Data("fresh local progress".utf8).write(to: roots.file("datasu.ksd")!)
        try Data("local slot".utf8).write(to: roots.file("data_0010_01.bmp")!)
        await b.set(cloud: ["datasu.ksd": Array("PC progress".utf8),
                           "data_0010_01.bmp": Array("new PC slot".utf8), "savecheck": Array("check".utf8)])
        let conflict = try await s.syncCloud(appID: 367520, roots: roots, backups: backups,
                                             resolve: ["data_0010_01.bmp": .steam])
        XCTAssertTrue(conflict.uploaded.isEmpty)
        XCTAssertTrue(conflict.failed.isEmpty)
        XCTAssertEqual(text(roots.file("datasu.ksd")!), "PC progress")
        XCTAssertEqual(text(roots.mirrorFile("datasu.ksd")!), "PC progress")
        let remoteProgress = await b.cloudFile("datasu.ksd")
        XCTAssertEqual(remoteProgress, Array("PC progress".utf8))
    }

    func testRestoreRefusesAgreementWhenAnotherWriterChangesDownloadedBytes() async throws {
        let b = FakeBackend(), name = "datasu.ksd"
        await b.set(cloud: [name: Array("Steam progress".utf8), "savecheck": Array("check".utf8)])
        roots.gameSaveMirror = dir.appendingPathComponent("native")
        let source = roots.file(name)!
        await b.onCloudDownload { file in
            if file == "savecheck" { try? Data("interference".utf8).write(to: source) }
        }
        let s = try await service(b)
        let broken = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, restoreSteam: true)
        XCTAssertNotNil(broken.failed[name], "a successful write must not establish a false agreement")
        let audit = await s.cloudSaveEvidence(appID: 367520, roots: roots)
        XCTAssertTrue(audit.contains("agreed-sha1=absent"))
        await b.onCloudDownload(nil)
        let retry = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, restoreSteam: true)
        XCTAssertTrue(retry.failed.isEmpty)
        XCTAssertEqual(text(source), "Steam progress")
        XCTAssertEqual(text(roots.mirrorFile(name)!), "Steam progress")
    }
    func testBackupRecoveryKeepsCurrentCopiesAndRequiresAChoiceBeforeAnyUpload() async throws {
        let b = FakeBackend(), name = "datasu.ksd", app: UInt32 = 1144400
        roots.gameSaveMirror = dir.appendingPathComponent("native")
        await b.set(cloud: [name: Array("previous Steam progress".utf8)])
        let s = try await service(b)
        _ = try await s.syncCloud(appID: app, roots: roots, backups: backups)
        try Data("new phone progress".utf8).write(to: roots.file(name)!)
        _ = try await s.syncCloud(appID: app, roots: roots, backups: backups)
        let points = Cloud.Backups.recoveryPoints(in: backups, appID: app)
        let point = try XCTUnwrap(points.first { $0.source == "steam" })
        XCTAssertEqual(point.names, [name])
        let restored = try await s.restoreCloudBackup(appID: app, roots: roots, backups: backups, id: point.id)
        XCTAssertTrue(restored.uploaded.isEmpty)
        XCTAssertEqual(restored.conflicts.map(\.name), [name])
        XCTAssertEqual(restored.conflicts.first?.recoveredBackup, true)
        XCTAssertNil(restored.conflicts.first?.localCopiesDiffer)
        XCTAssertEqual(text(roots.file(name)!), "previous Steam progress")
        XCTAssertEqual(text(roots.mirrorFile(name)!), "previous Steam progress")
        let next = try await s.syncCloud(appID: app, roots: roots, backups: backups)
        XCTAssertTrue(next.uploaded.isEmpty)
        XCTAssertEqual(next.conflicts.map(\.name), [name])
        XCTAssertEqual(next.conflicts.first?.recoveredBackup, true)
        XCTAssertEqual(next.conflicts.first?.phoneTime, restored.conflicts.first?.phoneTime)
        let untouched = await b.cloudFile(name)
        XCTAssertEqual(untouched, Array("new phone progress".utf8))
        let losing = TitleInstaller.regularFiles(under: backups).compactMap { text(backups.appendingPathComponent($0)) }
        XCTAssertTrue(losing.contains("new phone progress"))
        let accepted = try await s.syncCloud(appID: app, roots: roots, backups: backups, resolve: [name: .phone])
        XCTAssertEqual(accepted.uploaded, [name])
    }

    func testRecoveryIgnoresLinksUnknownFilesAndOtherTitlesAndRejectsOversizedCopies() throws {
        let fm = FileManager.default, app: UInt32 = 1144400
        let folder = Cloud.Backups.snapshotFolder(in: backups, appID: app, at: Date())
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: folder.appendingPathComponent("credentials.json.steam"))
        let outside = dir.appendingPathComponent("outside")
        try Data("outside".utf8).write(to: outside)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("datasu.ksd.steam"), withDestinationURL: outside)
        XCTAssertTrue(Cloud.Backups.recoveryPoints(in: backups, appID: app).isEmpty)
        XCTAssertThrowsError(try Cloud.Backups.recoveryFiles(in: backups, appID: app, id: "../outside|steam"))
        try fm.removeItem(at: folder.appendingPathComponent("datasu.ksd.steam"))
        try Data(repeating: 1, count: (2 << 20) + 1).write(to: folder.appendingPathComponent("datasu.ksd.steam"))
        let point = try XCTUnwrap(Cloud.Backups.recoveryPoints(in: backups, appID: app).first)
        XCTAssertThrowsError(try Cloud.Backups.recoveryFiles(in: backups, appID: app, id: point.id))
        XCTAssertTrue(Cloud.Backups.recoveryPoints(in: backups, appID: 367520).isEmpty)
        XCTAssertEqual(text(outside), "outside")
    }

    func testBackupSnapshotsWithinOneSecondRemainDistinctAndInventoryGroupsSlots() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let a = Cloud.Backups.snapshotFolder(in: backups, appID: 1144400, at: now)
        let b = Cloud.Backups.snapshotFolder(in: backups, appID: 1144400, at: now)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(Cloud.Backups.date(ofFolder: a.lastPathComponent), now)
        let inventory = Cloud.SaveInventory(names: ["data_0010_01.bmp", "DATA_0010_01.BMP", "data_0010_02.bmp",
            "data_quick_01.bmp", "data_continue.bmp", "private.bmp", "../data_0010_03.bmp"])
        XCTAssertEqual(inventory.manualGroups, ["0010": 2])
        XCTAssertEqual(inventory.manualPages, [10])
        XCTAssertEqual(inventory.manual, 2); XCTAssertEqual(inventory.quick, 1); XCTAssertTrue(inventory.hasContinue)
    }

    func testRecoveryUsesSteamSpellingSoUppercaseBackupsCannotBypassTheConflictGate() async throws {
        let b = FakeBackend(), app: UInt32 = 1144400
        roots.gameSaveMirror = dir.appendingPathComponent("native")
        await b.set(cloud: ["datasu.ksd": Array("current Steam".utf8)])
        let s = try await service(b)
        _ = try await s.syncCloud(appID: app, roots: roots, backups: backups)
        let folder = Cloud.Backups.snapshotFolder(in: backups, appID: app, at: Date())
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("older backup".utf8).write(to: folder.appendingPathComponent("DATASU.KSD.steam"))
        let point = try XCTUnwrap(Cloud.Backups.recoveryPoints(in: backups, appID: app).first)
        let restored = try await s.restoreCloudBackup(appID: app, roots: roots, backups: backups, id: point.id)
        XCTAssertEqual(restored.conflicts.map(\.name), ["datasu.ksd"])
        let next = try await s.syncCloud(appID: app, roots: roots, backups: backups)
        XCTAssertTrue(next.uploaded.isEmpty)
        XCTAssertEqual(next.conflicts.map(\.name), ["datasu.ksd"])
        let remote = await b.cloudFile("datasu.ksd")
        XCTAssertEqual(remote, Array("current Steam".utf8))
    }

    func testFailedSteamRestoreKeepsItsDirectionAcrossAnOrdinaryRetry() async throws {
        let b = FakeBackend(), name = "datasu.ksd"
        roots.gameSaveMirror = dir.appendingPathComponent("native")
        await b.set(cloud: [name: Array("PC original".utf8)])
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        try Data("fresh phone progress".utf8).write(to: roots.file(name)!)
        await b.replaceCloudDownload(Array("bad download".utf8))
        let failed = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, restoreSteam: true)
        XCTAssertNotNil(failed.failed[name])
        await b.replaceCloudDownload(nil)
        let retry = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        XCTAssertTrue(retry.uploaded.isEmpty)
        XCTAssertEqual(retry.downloaded, [name])
        XCTAssertEqual(text(roots.file(name)!), "PC original")
        let remote = await b.cloudFile(name)
        XCTAssertEqual(remote, Array("PC original".utf8))
    }

    private func recoveredOfflineFixture() async throws -> (FakeBackend, SteamService, String) {
        let backend = FakeBackend(), name = "datasu.ksd", app: UInt32 = 1144400
        roots.gameSaveMirror = dir.appendingPathComponent("native")
        await backend.set(cloud: [name: Array("old recovered progress".utf8)])
        let service = try await self.service(backend)
        _ = try await service.syncCloud(appID: app, roots: roots, backups: backups)
        try Data("fresh progress".utf8).write(to: roots.file(name)!)
        _ = try await service.syncCloud(appID: app, roots: roots, backups: backups)
        let point = try XCTUnwrap(Cloud.Backups.recoveryPoints(in: backups, appID: app).first { $0.source == "steam" })
        _ = try await service.restoreCloudBackup(appID: app, roots: roots, backups: backups, id: point.id)
        return (backend, service, name)
    }

    func testRecoveredPhoneChoiceRetriesBusyBeforeBackingUpAndUploading() async throws {
        let (backend, service, name) = try await recoveredOfflineFixture()
        let before = await backend.count("download \(name)")
        await backend.failCloudDownloads(name, with: Array(repeating: .eresult(.busy, context: "Cloud.ClientFileDownload#1"), count: 2))
        let result = try await service.syncCloud(appID: 1144400, roots: roots, backups: backups, resolve: [name: .phone])
        XCTAssertTrue(result.failed.isEmpty); XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual(result.uploaded, [name])
        let after = await backend.count("download \(name)"), remote = await backend.cloudFile(name)
        XCTAssertEqual(after - before, 3)
        XCTAssertEqual(remote, Array("old recovered progress".utf8))
        let versions = TitleInstaller.regularFiles(under: backups).compactMap { text(backups.appendingPathComponent($0)) }
        XCTAssertTrue(versions.contains("fresh progress"), "the losing cloud version must still be backed up")
    }

    func testFailedRecoveredPhoneChoiceRetainsConflictAcrossRestartAndNeverAutoUploads() async throws {
        let (backend, service, name) = try await recoveredOfflineFixture()
        let before = await backend.count("upload \(name)")
        await backend.failCloudDownloads(name, with: Array(repeating: .eresult(.busy, context: "Cloud.ClientFileDownload#1"), count: 4))
        let failed = try await service.syncCloud(appID: 1144400, roots: roots, backups: backups, resolve: [name: .phone])
        XCTAssertNotNil(failed.failed[name]); XCTAssertTrue(failed.uploaded.isEmpty)
        XCTAssertEqual(failed.conflicts.map(\.name), [name]); XCTAssertEqual(failed.conflicts.first?.recoveredBackup, true)
        XCTAssertEqual(text(roots.file(name)!), "old recovered progress")
        XCTAssertEqual(text(roots.mirrorFile(name)!), "old recovered progress")
        let restarted = try await self.service(backend)
        let retry = try await restarted.syncCloud(appID: 1144400, roots: roots, backups: backups)
        XCTAssertTrue(retry.uploaded.isEmpty); XCTAssertEqual(retry.conflicts.first?.recoveredBackup, true)
        let after = await backend.count("upload \(name)"), remote = await backend.cloudFile(name)
        XCTAssertEqual(after, before); XCTAssertEqual(remote, Array("fresh progress".utf8))
    }

    func testRecoveredSteamChoiceRetriesBusyAndReplacesBothLocalCopiesWithoutUpload() async throws {
        let (backend, service, name) = try await recoveredOfflineFixture()
        let before = await backend.count("download \(name)")
        await backend.failCloudDownloads(name, with: [.eresult(.busy, context: "Cloud.ClientFileDownload#1")])
        let result = try await service.syncCloud(appID: 1144400, roots: roots, backups: backups, resolve: [name: .steam])
        XCTAssertTrue(result.failed.isEmpty); XCTAssertTrue(result.conflicts.isEmpty); XCTAssertTrue(result.uploaded.isEmpty)
        XCTAssertEqual(result.downloaded, [name])
        XCTAssertEqual(text(roots.file(name)!), "fresh progress"); XCTAssertEqual(text(roots.mirrorFile(name)!), "fresh progress")
        let after = await backend.count("download \(name)")
        XCTAssertEqual(after - before, 2)
    }

    func testRecoveredOfflineVerificationMakesNoNetworkCallsAndKeepsConflict() async throws {
        let (backend, service, name) = try await recoveredOfflineFixture()
        let before = await backend.calls
        try await service.preparePhoneCloudOfflinePlay(appID: 1144400, roots: roots)
        let after = await backend.calls, kept = await service.keptCloud(appID: 1144400)
        XCTAssertEqual(before, after)
        XCTAssertEqual(kept?.conflicts.first?.name, name); XCTAssertEqual(kept?.conflicts.first?.recoveredBackup, true)
        let retry = try await service.syncCloud(appID: 1144400, roots: roots, backups: backups)
        XCTAssertTrue(retry.uploaded.isEmpty); XCTAssertEqual(retry.conflicts.map(\.name), [name])
    }

    func testRecoveredOfflineVerificationRejectsMismatchedOrMissingCopies() async throws {
        let (backend, service, name) = try await recoveredOfflineFixture()
        try Data("different native progress".utf8).write(to: roots.mirrorFile(name)!)
        do { try await service.preparePhoneCloudOfflinePlay(appID: 1144400, roots: roots); XCTFail("must reject differing saves") }
        catch {}
        try FileManager.default.removeItem(at: roots.mirrorFile(name)!)
        do { try await service.preparePhoneCloudOfflinePlay(appID: 1144400, roots: roots); XCTFail("must reject a missing copy") }
        catch {}
        let remote = await backend.cloudFile(name)
        XCTAssertEqual(remote, Array("fresh progress".utf8)); XCTAssertEqual(text(roots.file(name)!), "old recovered progress")
    }

    func testIncompleteSteamRestoreCannotBecomeRecoveredOfflinePlay() async throws {
        let (backend, service, name) = try await recoveredOfflineFixture()
        await backend.replaceCloudDownload(Array("bad download".utf8))
        let failed = try await service.syncCloud(appID: 1144400, roots: roots, backups: backups, restoreSteam: true)
        XCTAssertNotNil(failed.failed[name])
        do { try await service.preparePhoneCloudOfflinePlay(appID: 1144400, roots: roots); XCTFail("must reject an incomplete Steam restore") }
        catch {}
        XCTAssertEqual(text(roots.file(name)!), "old recovered progress")
    }

    func testOfflinePhonePreparationRepairsLostLegacyMarkersWithoutInventingRecoveryEvidence() async throws {
        let (backend, _, name) = try await recoveredOfflineFixture()
        let record = dir.appendingPathComponent("state/steam-cloud/1144400.json")
        for removeRecord in [false, true] {
            if removeRecord {
                try FileManager.default.removeItem(at: record)
            } else {
                var old = try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as! [String: Any]
                old["conflicts"] = [] // the r23 failure path dropped its recovery marker
                try JSONSerialization.data(withJSONObject: old).write(to: record)
            }
            let service = try await self.service(backend)
            let before = await backend.calls
            try await service.preparePhoneCloudOfflinePlay(appID: 1144400, roots: roots)
            let after = await backend.calls, kept = await service.keptCloud(appID: 1144400)
            XCTAssertEqual(before, after)
            XCTAssertEqual(kept?.conflicts.map(\.name), [name]); XCTAssertNil(kept?.conflicts.first?.recoveredBackup)
            let retry = try await service.syncCloud(appID: 1144400, roots: roots, backups: backups)
            XCTAssertTrue(retry.uploaded.isEmpty); XCTAssertEqual(retry.conflicts.map(\.name), [name])
            XCTAssertEqual(text(roots.file(name)!), "old recovered progress")
            let remote = await backend.cloudFile(name)
            XCTAssertEqual(remote, Array("fresh progress".utf8))
        }
    }

    func testOfflinePhonePreparationRefusesLaunchWhenItCannotPersistTheUnresolvedChoice() async throws {
        let (backend, service, name) = try await recoveredOfflineFixture()
        let record = dir.appendingPathComponent("state/steam-cloud/1144400.json")
        try FileManager.default.removeItem(at: record)
        try FileManager.default.createDirectory(at: record, withIntermediateDirectories: false)
        do { try await service.preparePhoneCloudOfflinePlay(appID: 1144400, roots: roots); XCTFail("must retain protection before launch") }
        catch {}
        XCTAssertEqual(text(roots.file(name)!), "old recovered progress")
        let remote = await backend.cloudFile(name)
        XCTAssertEqual(remote, Array("fresh progress".utf8))
    }

    func testLegacyDroppedPhoneChoiceRequiresConfirmationBeforeAnyAutomaticUpload() async throws {
        let (backend, _, name) = try await recoveredOfflineFixture()
        let url = dir.appendingPathComponent("state/steam-cloud/1144400.json")
        var old = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        old["conflicts"] = []
        old.removeValue(forKey: "saveChoiceVersion")
        try JSONSerialization.data(withJSONObject: old).write(to: url)
        let service = try await self.service(backend)
        let before = await backend.count("upload \(name)")
        let upgrade = try await service.syncCloud(appID: 1144400, roots: roots, backups: backups)
        XCTAssertTrue(upgrade.uploaded.isEmpty); XCTAssertEqual(upgrade.conflicts.map(\.name), [name])
        let after = await backend.count("upload \(name)"), remote = await backend.cloudFile(name)
        XCTAssertEqual(after, before); XCTAssertEqual(remote, Array("fresh progress".utf8))
        let chosen = try await service.syncCloud(appID: 1144400, roots: roots, backups: backups, resolve: [name: .phone])
        XCTAssertEqual(chosen.uploaded, [name]); XCTAssertTrue(chosen.conflicts.isEmpty)
        try Data("later phone play".utf8).write(to: roots.file(name)!)
        let later = try await service.syncCloud(appID: 1144400, roots: roots, backups: backups)
        XCTAssertEqual(later.uploaded, [name], "migration must not ask again after a successful explicit choice")
    }

    func testRestoreMustPersistDirectionBeforeReplacingAnyFile() async throws {
        let b = FakeBackend(), name = "datasu.ksd"
        await b.set(cloud: [name: Array("PC".utf8)])
        let s = try await service(b)
        _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups)
        try Data("phone original".utf8).write(to: roots.file(name)!)
        let record = dir.appendingPathComponent("state/steam-cloud/367520.json")
        try FileManager.default.removeItem(at: record)
        try FileManager.default.createDirectory(at: record, withIntermediateDirectories: false)
        do {
            _ = try await s.syncCloud(appID: 367520, roots: roots, backups: backups, restoreSteam: true)
            XCTFail("state write failure must stop restoration before changing any save")
        } catch {}
        XCTAssertEqual(text(roots.file(name)!), "phone original")
    }

}
