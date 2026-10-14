// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Player-visible startup evidence. A short zero-code exit is not proof of a successful play.
public enum LaunchDiagnostics {
    public static func endedBeforeDrawing(exitCode: UInt32, drewFrame: Bool, elapsed: TimeInterval) -> Bool {
        !drewFrame && elapsed.isFinite && elapsed >= 0 && elapsed <= 10
    }

    /// Wine's msgbox channel includes the Windows dialog text even when no dialog was drawn.
    public static func lastWindowsMessage(in log: String) -> String? {
        // PlayPort's patched Wine logs MessageBoxIndirectW [msgbox], unlike
        // upstream Wine's :msgbox: trace. The old parser ignored the former.
        for line in log.split(separator: "\n").reversed() {
            if let mark = line.range(of: "[msgbox]"),
               let start = line[mark.upperBound...].range(of: " text L\"") {
                let body = String(line[start.upperBound...].prefix(while: { $0 != "\"" }))
                let message = decodeWineMessage(body).trimmingCharacters(in: .whitespacesAndNewlines)
                if !message.isEmpty { return String(message.prefix(512)) }
            }
            if let mark = line.range(of: ":msgbox:"),
               let space = line[mark.upperBound...].firstIndex(of: " ") {
                let message = line[line.index(after: space)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !message.isEmpty { return String(message.prefix(512)) }
            }
        }
        return nil
    }

    /// Decode Wine's \hhhh UTF-16 code-unit escapes without disclosing
    /// unrelated diagnostic lines or absolute container paths.
    private static func decodeWineMessage(_ input: String) -> String {
        let units = Array(input.utf16.prefix(2048))
        var output: [UInt16] = []
        var i = 0
        while i < units.count {
            if units[i] == 92 && i + 4 < units.count {
                let digits = units[(i + 1)...(i + 4)]
                if digits.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                   let value = UInt16(String(decoding: digits, as: UTF16.self), radix: 16) {
                    output.append(value)
                    i += 5
                    continue
                }
            }
            output.append(units[i])
            i += 1
        }
        return String(decoding: output, as: UTF16.self)
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
    public static func inventory(in root: URL, steamAppID: UInt32? = nil) -> String {
        let heading = "Game folder inventory (relative names and bytes; scan limited to 2048 entries, depth 4)\n"
        let fm = FileManager.default
        let files = entries(in: root)
        var report = heading
        if files.isEmpty {
            let status = fm.fileExists(atPath: root.path)
                ? "(no regular files enumerated; check directory access and install layout)"
                : "(game directory unavailable when report was created)"
            report += status + "\n"
        } else {
            report += files.map { "\($0.size)\t\($0.relative)" }.joined(separator: "\n") + "\n"
        }
        if steamAppID == 1144400 {
            // Direct stat probes distinguish missing assets from a broken
            // directory enumerator. No file contents or private paths exported.
            report += "Senren Banka required-file probes (metadata only):\n"
            for relative in ["SenrenBanka.exe", "data.xp3", "patch.xp3", "scn.xp3", "plugin"] {
                let url = root.appendingPathComponent(relative)
                if let attributes = try? fm.attributesOfItem(atPath: url.path) {
                    let type = attributes[.type] as? FileAttributeType
                    let kind = type == .typeDirectory ? "directory" : type == .typeRegular ? "file" : "other"
                    let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
                    report += "\(relative)\t\(kind)\t\(size) bytes\n"
                } else {
                    report += "\(relative)\tmissing or unreadable\n"
                }
            }
        }
        return report
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
