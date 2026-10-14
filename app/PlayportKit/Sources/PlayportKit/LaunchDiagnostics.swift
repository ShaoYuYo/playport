// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Player-visible startup evidence. A short zero-code exit is not proof of a successful play.
public enum LaunchDiagnostics {
    public static func endedBeforeDrawing(exitCode: UInt32, drewFrame: Bool, elapsed: TimeInterval) -> Bool {
        !drewFrame && elapsed.isFinite && elapsed >= 0 && elapsed <= 10
    }

    /// Wine's msgbox channel includes the Windows dialog text even when no dialog was drawn.
    public static func lastWindowsMessage(in log: String) -> String? {
        guard let line = log.split(separator: "\n").last(where: { $0.contains(":msgbox:") }),
              let channel = line.range(of: ":msgbox:"),
              let space = line[channel.upperBound...].firstIndex(of: " ") else { return nil }
        let text = line[line.index(after: space)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(512))
    }

    /// Read only this launch's bounded tail, never a preceding game's dialog.
    public static func windowsMessage(in log: URL, after offset: UInt64) -> String? {
        guard let file = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? file.close() }
        guard let end = try? file.seekToEnd(), end > offset else { return nil }
        do {
            try file.seek(toOffset: max(offset, end > 128 << 10 ? end - (128 << 10) : 0))
            guard let bytes = try file.read(upToCount: 128 << 10) else { return nil }
            return lastWindowsMessage(in: String(decoding: bytes, as: UTF8.self))
        } catch { return nil }
    }

    /// Only logs inside the selected game's folder. No links, credentials, saves or game content.
    /// Bounded enumeration and bytes keep a report practical on an iPhone.
    public static func gameLogs(in root: URL) -> [URL] {
        var bytes = 0
        return entries(in: root).compactMap { item in
            guard item.url.pathExtension.lowercased() == "log", item.size > 0, item.size <= 2 << 20,
                  bytes + item.size <= 8 << 20 else { return nil }
            bytes += item.size
            return item.url
        }.prefix(32).map { $0 }
    }

    /// Names and sizes only: enough to spot a missing archive/plugin or a language depot mismatch.
    public static func inventory(in root: URL) -> String {
        "Game folder inventory (relative names and bytes; scan limited to 2048 entries, depth 4)\n"
        + entries(in: root).map { "\($0.size)\t\($0.relative)" }.joined(separator: "\n") + "\n"
    }

    private struct Entry {
        var url: URL
        var relative: String
        var size: Int
    }

    private static func entries(in root: URL) -> [Entry] {
        let fm = FileManager.default
        let original = root.standardizedFileURL
        let base = original.resolvingSymlinksInPath()
        guard let rootValues = try? original.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              rootValues.isDirectory == true, rootValues.isSymbolicLink != true,
              let walk = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                                       options: [.skipsHiddenFiles]) else { return [] }
        let prefix = base.path + "/"
        var result: [Entry] = [], visited = 0
        for case let url as URL in walk {
            visited += 1
            if visited > 2048 { break }
            guard url.path.hasPrefix(prefix), walk.level <= 4 else { walk.skipDescendants(); continue }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isSymbolicLink != true else { walk.skipDescendants(); continue }
            guard values.isRegularFile == true else { continue }
            let name = String(url.path.dropFirst(prefix.count)).replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
            result.append(Entry(url: url, relative: name, size: values.fileSize ?? 0))
        }
        return result.sorted { $0.relative < $1.relative }
    }
}
