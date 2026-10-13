// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A KiriKiri2/Z game-data candidate, not evidence that an unmodified
/// commercial title is compatible with an iOS-native engine.
public struct KirikiriGameData: Equatable, Sendable {
    /// Archive name relative to the game directory; no executable is launched.
    public let entryArchive: String
    /// All validated, top-level XP3 archives, in deterministic order.
    public let archives: [String]
    /// Loose script at the game root; an archive can include it instead.
    public let hasLooseStartupScript: Bool
}

/// Reads the XP3 container signature instead of assuming every *.xp3 name
/// is valid. Never extracts, decrypts or changes any game data.
public enum KirikiriProbe {
    // XP3\r\n \n\x1A\x8Bg\x01
    public static let signature: [UInt8] = [0x58,0x50,0x33,0x0D,0x0A,0x20,0x0A,0x1A,0x8B,0x67,0x01]

    /// Flat scan only. No recursion or reads proportional to the game size:
    /// Steam games can exceed 7 GiB. Links are never followed outside root.
    public static func inspect(directory: URL, fileManager fm: FileManager = .default) -> KirikiriGameData? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys),
                                                     options: [.skipsHiddenFiles]) else { return nil }
        let regular = files.filter { url in
            guard let info = try? url.resourceValues(forKeys: keys) else { return false }
            return info.isRegularFile == true && info.isSymbolicLink != true
        }
        let archives = regular.filter { $0.pathExtension.caseInsensitiveCompare("xp3") == .orderedSame && validXP3($0) }
            .map(\.lastPathComponent).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let entry = archives.first { $0.caseInsensitiveCompare("data.xp3") == .orderedSame }
            ?? archives.first { !isPatchOnly($0) }
        guard let entry else { return nil }
        let scripts = Set(regular.map { $0.lastPathComponent.lowercased() })
        return KirikiriGameData(entryArchive: entry, archives: archives,
                                hasLooseStartupScript: scripts.contains("startup.tjs") || scripts.contains("initialize.tjs"))
    }

    private static func validXP3(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard let bytes = try? h.read(upToCount: signature.count) else { return false }
        return Array(bytes) == signature
    }

    private static func isPatchOnly(_ name: String) -> Bool {
        let stem = (name as NSString).deletingPathExtension.lowercased()
        return stem.hasPrefix("patch") || stem.hasPrefix("update") || stem == "plugin"
    }
}
