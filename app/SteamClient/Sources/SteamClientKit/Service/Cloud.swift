// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A game's Steam Cloud files on the phone (docs/plans/finished.md#steam-for-games,
/// phase 4).
///
/// Steam names a cloud file by a root token and a path:
/// `%WinAppDataLocalLow%Team Cherry/Hollow Knight/user1.dat`. A file a game
/// writes through the Steam API itself (ISteamRemoteStorage) has no token;
/// under the emulator it is in `GSE Saves/<appid>/remote/`. Which local files
/// are cloud files comes from PICS `ufs/savefiles` (root, path, pattern,
/// recursive, platforms).
public enum Cloud {
    /// Where each root is in the prefix.
    public struct Roots: Sendable, Equatable {
        /// `C:\users\playport`.
        public var user: URL
        /// The game's folder under `C:\Games`.
        public var gameInstall: URL
        /// The emulator's remote storage for the game: `GSE Saves/<appid>/remote`.
        public var remote: URL
        /// A verified title's native save directory, for games that can switch
        /// between Steam RemoteStorage and direct file storage. Only recognised
        /// save names are reconciled; settings, anchors and logs stay local.
        public var gameSaveMirror: URL?

        public init(user: URL, gameInstall: URL, remote: URL, gameSaveMirror: URL? = nil) {
            self.user = user
            self.gameInstall = gameInstall
            self.remote = remote
            self.gameSaveMirror = gameSaveMirror
        }

        public func mirrorFile(_ name: String) -> URL? {
            guard let gameSaveMirror, !name.contains("/"), !name.contains("\\"), !name.contains("%"),
                  Cloud.isMirroredSave(name) else { return nil }
            let spelling = Cloud.resolve([name], in: gameSaveMirror).lastPathComponent
            return try? InstallFS.resolveInside(gameSaveMirror, spelling, createParents: false)
        }

        /// A root token's folder; nil for a root Playport does not map.
        public func folder(_ token: String) -> URL? {
            switch token.lowercased() {
            case "": remote
            case "gameinstall": gameInstall
            case "winmydocuments": user.appendingPathComponent("Documents", isDirectory: true)
            case "winappdatalocal": user.appendingPathComponent("AppData/Local", isDirectory: true)
            case "winappdatalocallow": user.appendingPathComponent("AppData/LocalLow", isDirectory: true)
            case "winappdataroaming": user.appendingPathComponent("AppData/Roaming", isDirectory: true)
            case "winsavedgames": user.appendingPathComponent("Saved Games", isDirectory: true)
            default: nil
            }
        }

        /// The local file for a cloud name; nil when its root is not mapped or
        /// its path leaves the root.
        public func file(_ name: String) -> URL? {
            let (token, rest) = Cloud.split(name)
            guard let base = folder(token) else { return nil }
            let parts = rest.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
            guard !parts.isEmpty, !parts.contains(".."), !parts.contains(".") else { return nil }
            return Cloud.resolve(parts, in: base)
        }
    }

    static func isMirroredSave(_ name: String) -> Bool {
        let n = name.lowercased()
        return n == "savecheck" || (n.hasPrefix("data") && n != "data_anchor.ksd"
            && (n.hasSuffix(".ksd") || n.hasSuffix(".bmp")))
    }

    static func mirroredFiles(_ roots: Roots) -> [String: URL] {
        guard let dir = roots.gameSaveMirror else { return [:] }
        var result: [String: URL] = [:]
        for name in TitleInstaller.regularFiles(under: dir) where isMirroredSave(name) {
            if let url = roots.mirrorFile(name) { result[name] = url }
        }
        return result
    }

    /// Steam's spelling of a root token, as its file list names a file a
    /// Windows client uploaded: a PICS rule may spell it in another case
    /// (Portal 2's `gameinstall`). A token Playport does not map stays as given.
    static func canonicalRoot(_ token: String) -> String {
        let steam = ["GameInstall", "WinMyDocuments", "WinAppDataLocal", "WinAppDataLocalLow", "WinAppDataRoaming", "WinSavedGames"]
        return steam.first { $0.lowercased() == token.lowercased() } ?? token
    }

    /// The local files under the names Steam already uses. Steam takes cloud
    /// names without case (an upload of a name that differs from a stored one
    /// only in case is refused as a duplicate), and so does the prefix's file
    /// system, so a local name that matches one of `names` without case takes
    /// that spelling; an earlier entry of `names` wins. Local names that become
    /// one keep the file of the first in sorted order.
    public static func named(_ files: [String: URL], like names: [String]) -> [String: URL] {
        var spelling: [String: String] = [:]
        for n in names where spelling[n.lowercased()] == nil { spelling[n.lowercased()] = n }
        var out: [String: URL] = [:]
        for (name, url) in files.sorted(by: { $0.key < $1.key }) {
            let key = spelling[name.lowercased()] ?? name
            if out[key] == nil { out[key] = url }
        }
        return out
    }

    /// `%Token%rest` into the token (empty for none) and the rest.
    static func split(_ name: String) -> (String, String) {
        guard name.hasPrefix("%"), let end = name.dropFirst().firstIndex(of: "%") else { return ("", name) }
        return (String(name[name.index(after: name.startIndex)..<end]), String(name[name.index(after: end)...]))
    }

    /// Each component matched without case against what is on disk, as the
    /// guest sees it; components that do not exist yet are taken as given.
    static func resolve(_ parts: [String], in base: URL) -> URL {
        var at = base
        for p in parts {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: at.path)) ?? []
            at = at.appendingPathComponent(names.first { $0 == p } ?? names.first { $0.lowercased() == p.lowercased() } ?? p)
        }
        return at
    }

    /// One `ufs/savefiles` rule.
    public struct SaveRule: Sendable, Equatable {
        public var root: String
        public var path: String
        public var pattern: String
        public var recursive: Bool
    }

    /// The app's Windows save rules (PICS `ufs/savefiles`; a rule for other
    /// platforms only is skipped).
    public static func rules(_ app: KeyValue) -> [SaveRule] {
        (app.path("ufs", "savefiles")?.children ?? []).compactMap { r in
            let platforms = (r["platforms"]?.children ?? []).compactMap(\.value).map { $0.lowercased() }
            guard platforms.isEmpty || platforms.contains("windows") || platforms.contains("all") else { return nil }
            return SaveRule(root: r["root"]?.value ?? "", path: r["path"]?.value ?? "", pattern: r["pattern"]?.value ?? "*",
                            recursive: r["recursive"]?.value == "1")
        }
    }

    /// The local files the rules cover, by cloud name, and the emulator's
    /// remote storage (every file under it).
    public static func localFiles(rules: [SaveRule], roots: Roots, steamID: UInt64) -> [String: URL] {
        var out: [String: URL] = [:]
        for r in rules + [SaveRule(root: "", path: "", pattern: "*", recursive: true)] {
            guard let base = roots.folder(r.root) else { continue }
            let rel = substitute(r.path, steamID: steamID)
                .split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init).filter { $0 != "." }
            guard !rel.contains("..") else { continue }
            let dir = rel.isEmpty ? base : resolve(rel, in: base)
            for file in TitleInstaller.regularFiles(under: dir) {
                let parts = file.split(separator: "/")
                guard r.recursive || parts.count == 1, glob(r.pattern, String(parts.last ?? "")) else { continue }
                let prefix = r.root.isEmpty ? "" : "%\(canonicalRoot(r.root))%"
                let path = (rel + [file]).joined(separator: "/")
                out[prefix + path] = dir.appendingPathComponent(file)
            }
        }
        return out
    }

    /// The path tokens Steam puts in a rule for the account.
    static func substitute(_ path: String, steamID: UInt64) -> String {
        path.replacingOccurrences(of: "{64BitSteamID}", with: String(steamID))
            .replacingOccurrences(of: "{Steam3AccountID}", with: String(steamID & 0xFFFF_FFFF))
    }

    /// `*` and `?` against a file name, without case.
    static func glob(_ pattern: String, _ name: String) -> Bool {
        let p = Array(pattern.lowercased()), n = Array(name.lowercased())
        var memo = [[Bool?]](repeating: [Bool?](repeating: nil, count: n.count + 1), count: p.count + 1)
        func m(_ i: Int, _ j: Int) -> Bool {
            if let v = memo[i][j] { return v }
            let r: Bool
            if i == p.count { r = j == n.count }
            else if p[i] == "*" { r = m(i + 1, j) || (j < n.count && m(i, j + 1)) }
            else { r = j < n.count && (p[i] == "?" || p[i] == n[j]) && m(i + 1, j + 1) }
            memo[i][j] = r
            return r
        }
        return m(0, 0)
    }

    /// Senren's native filename mapping, verified with its own save reader.
    public struct SaveInventory: Sendable, Equatable {
        public var manualGroups: [String: Int] = [:]
        public var quick = 0
        public var hasContinue = false
        public init(names: [String]) {
            for name in Set(names.map { $0.lowercased() }) {
                if name == "data_continue.bmp" { hasContinue = true }
                else if name.range(of: #"^data_quick_[0-9]{2}\.bmp$"#, options: .regularExpression) != nil { quick += 1 }
                else if name.range(of: #"^data_[0-9]{4}_[0-9]{2}\.bmp$"#, options: .regularExpression) != nil {
                    manualGroups[String(name.dropFirst(5).prefix(4)), default: 0] += 1
                }
            }
        }
        public var manual: Int { manualGroups.values.reduce(0, +) }
        /// Group 0010 maps to the game's manual page 10; quick saves use a
        /// separate filename family and are shown on the quick-save tab.
        public var manualPages: [Int] {
            Set(manualGroups.keys.compactMap(Int.init).filter { $0 > 0 }).sorted()
        }
    }

    static func recoverableSenrenName(_ name: String) -> Bool {
        name.range(of: #"^(datas[cu]\.ksd|savecheck|data_(continue|quick_[0-9]{2}|[0-9]{4}_[0-9]{2})\.bmp)$"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: what to do

    /// A cloud file as Steam lists it.
    public struct Remote: Sendable, Equatable, Codable {
        public var name: String
        /// SHA-1 of the file's content, hex.
        public var sha: String
        public var size: UInt32
        public var time: UInt64
    }

    /// What the last sync left: Steam's change number and every file's SHA-1.
    public struct Baseline: Sendable, Equatable, Codable {
        public var changeNumber: UInt64
        public var files: [String: String]
    }

    public enum Action: String, Sendable, Equatable, Codable {
        case download, upload, conflict
    }

    /// Per file:
    /// - the same on both sides: nothing;
    /// - changed on one side since the last sync: that side wins;
    /// - changed on both, or different with no last sync to tell: a conflict,
    ///   which the player settles;
    /// - on Steam only: downloaded/restored; local deletions never delete
    ///   Steam's remaining copy;
    /// - on the phone only: uploaded when it is new or changed since the last
    ///   sync; a game's first sync uploads nothing.
    public static func plan(remote: [String: Remote], local: [String: String], baseline: Baseline?) -> [String: Action] {
        var out: [String: Action] = [:]
        for name in Set(remote.keys).union(local.keys) {
            let r = remote[name]?.sha, l = local[name], b = baseline?.files[name]
            switch (r, l) {
            case let (r?, l?):
                if r == l { continue }
                if b == nil { out[name] = .conflict }
                else if l == b { out[name] = .download }
                else if r == b { out[name] = .upload }
                else { out[name] = .conflict }
            case (_?, nil):
                // Never propagate deletion: a missing local copy is restored.
                out[name] = .download
            case (nil, let l?):
                if baseline != nil, b != l { out[name] = .upload }
            case (nil, nil):
                continue
            }
        }
        return out
    }

    /// A downloaded body as the file's content: as is, or the single entry of
    /// a zip Steam sends when the stored size differs from the raw size. It
    /// must hash to `sha` either way.
    public static func content(_ body: [UInt8], rawSize: UInt32, sha: String) throws -> [UInt8] {
        var data = body
        if body.count != Int(rawSize) || (body.starts(with: [0x50, 0x4B, 0x03, 0x04]) && SHA1.hash(body).hex != sha) {
            data = try ZipSingleEntry.extract(body, maxSize: Int(rawSize) + 1)
        }
        guard data.count == Int(rawSize), SHA1.hash(data).hex == sha else {
            throw SteamError.verificationFailed("cloud file does not match Steam's size and SHA-1")
        }
        return data
    }
}

extension Cloud {
    /// The copies a sync replaced: `<root>/<appid>/<time>/`, one folder per
    /// game and sync (SteamService.syncCloud). The side the player did not
    /// keep in a conflict, and a phone copy a download replaced, stay there
    /// for `keep` (30 days), then `prune` removes them.
    public enum Backups {
        public static let keep: TimeInterval = 30 * 24 * 3600

        /// A sync's folder name: its time in ISO 8601, with `-` for `:` (Files shows no colons).
        public static func folderName(for date: Date) -> String {
            ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
        }

        /// The time a folder name carries; nil for a name `folderName` did not make.
        public static func date(ofFolder name: String) -> Date? {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd'T'HH-mm-ssXXXXX"
            return f.date(from: String(name.split(separator: "_", maxSplits: 1).first ?? ""))
        }

        /// A unique directory per operation, including retries in one second.
        public static func snapshotFolder(in root: URL, appID: UInt32, at date: Date) -> URL {
            root.appendingPathComponent(String(appID), isDirectory: true)
                .appendingPathComponent(folderName(for: date) + "_" + UUID().uuidString.lowercased(), isDirectory: true)
        }

        public struct RecoveryPoint: Sendable, Equatable, Identifiable {
            public var id: String
            public var at: Date
            /// Previous Steam, previous phone, native, or remote backend copy.
            public var source: String
            public var names: [String]
        }

        static func regular(_ url: URL, directory: Bool = false) -> Bool {
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType)
                == (directory ? .typeDirectory : .typeRegular)
        }

        /// Only fixed title save names and direct, non-linked children qualify.
        /// Old backups may be partial: names are shown before choosing one.
        public static func recoveryPoints(in root: URL, appID: UInt32) -> [RecoveryPoint] {
            guard appID == 1144400 else { return [] }
            let app = root.resolvingSymlinksInPath().appendingPathComponent(String(appID))
            guard regular(app, directory: true) else { return [] }
            let dirs = ((try? FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent > $1.lastPathComponent }.prefix(256)
            var points: [RecoveryPoint] = []
            for dir in dirs where regular(dir, directory: true) {
                guard let at = date(ofFolder: dir.lastPathComponent) else { continue }
                let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                    .filter { regular($0) }.prefix(256)
                for source in ["steam", "previous", "game", "remote"] {
                    let suffix = source == "previous" ? "" : "." + source
                    let names = files.compactMap { file -> String? in
                        let n = file.lastPathComponent
                        guard suffix.isEmpty || n.hasSuffix(suffix) else { return nil }
                        let name = suffix.isEmpty ? n : String(n.dropLast(suffix.count))
                        return Cloud.recoverableSenrenName(name) ? name : nil
                    }.sorted()
                    if !names.isEmpty {
                        points.append(RecoveryPoint(id: dir.lastPathComponent + "|" + source, at: at, source: source, names: names))
                    }
                }
            }
            return Array(points.prefix(128))
        }

        static func recoveryFiles(in root: URL, appID: UInt32, id: String) throws -> [String: Data] {
            guard let point = recoveryPoints(in: root, appID: appID).first(where: { $0.id == id }),
                  point.names.count <= 64, let folder = id.split(separator: "|", maxSplits: 1).first else {
                throw SteamError.unsupported("save backup is unavailable")
            }
            let dir = root.resolvingSymlinksInPath().appendingPathComponent(String(appID)).appendingPathComponent(String(folder))
            var result: [String: Data] = [:], total = 0
            for name in point.names {
                let file = dir.appendingPathComponent(name + (point.source == "previous" ? "" : "." + point.source))
                guard regular(file), let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue,
                      size <= 2 << 20, total + size <= 32 << 20 else { throw SteamError.unsupported("unsafe save backup") }
                let data = try Data(contentsOf: file)
                guard data.count == size else { throw SteamError.transport("save backup changed; retry") }
                result[name] = data; total += size
            }
            return result
        }

        /// The sync folders under `root` older than `keep` at `now`. A folder
        /// whose name carries no time goes by its modification date.
        public static func expired(in root: URL, now: Date = Date(), keep: TimeInterval = Backups.keep) -> [URL] {
            let fm = FileManager.default
            let apps = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            var out: [URL] = []
            for app in apps.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let syncs = (try? fm.contentsOfDirectory(at: app, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                for sync in syncs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let made = date(ofFolder: sync.lastPathComponent)
                        ?? (try? sync.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    if let made, now.timeIntervalSince(made) > keep { out.append(sync) }
                }
            }
            return out
        }

        /// Removes the expired sync folders, and a game's folder left empty;
        /// returns what it removed.
        @discardableResult
        public static func prune(_ root: URL, now: Date = Date(), keep: TimeInterval = Backups.keep) -> [URL] {
            let fm = FileManager.default
            var removed: [URL] = []
            for url in expired(in: root, now: now, keep: keep) where (try? fm.removeItem(at: url)) != nil {
                removed.append(url)
                let app = url.deletingLastPathComponent()
                if (try? fm.contentsOfDirectory(atPath: app.path))?.isEmpty == true { try? fm.removeItem(at: app) }
            }
            return removed
        }
    }
}
