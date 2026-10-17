// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SteamClientKit

/// Player-visible startup evidence. A short zero-code exit is not proof of a successful play.
public enum LaunchDiagnostics {
    /// Actual bytes in the two known save backends, rather than just transfer
    /// counts. Fixed metadata only: never export save contents or account INIs.
    public static func senrenSaveState(prefix: URL, gameRoot: URL) -> String {
        let fm = FileManager.default
        let roaming = prefix.resolvingSymlinksInPath().appendingPathComponent("drive_c/users/playport/AppData/Roaming")
        let locations = [("steam", roaming.appendingPathComponent("GSE Saves/1144400/remote")),
                         ("native", roaming.appendingPathComponent("YuzuSoft/SenrenBanka"))]
        var report = "Save backend audit v1 (metadata and SHA256; no save contents)\n"
        var total = 0
        for (tag, dir) in locations {
            guard dir.resolvingSymlinksInPath().standardizedFileURL == dir.standardizedFileURL else {
                report += "\(tag): linked directory omitted\n"; continue
            }
            let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted().prefix(256)
            var count = 0
            for name in names {
                let n = name.lowercased()
                guard n == "savecheck" || n == "senrenbanka.cfu"
                    || (n.hasPrefix("data") && (n.hasSuffix(".ksd") || n.hasSuffix(".bmp"))) else { continue }
                let url = dir.appendingPathComponent(name)
                guard let attr = try? fm.attributesOfItem(atPath: url.path),
                      attr[.type] as? FileAttributeType == .typeRegular,
                      let size = (attr[.size] as? NSNumber)?.intValue, size <= 2 << 20,
                      total + size <= 32 << 20, count < 64, let data = try? Data(contentsOf: url) else { continue }
                let safe = n.replacingOccurrences(of: "\n", with: "_").replacingOccurrences(of: "\t", with: "_")
                report += "\(tag)/\(safe)\t\(data.count)\t\(SHA256Stream.hash(Array(data)).hex)\n"
                count += 1; total += data.count
            }
            report += "\(tag): \(count) file(s) audited\n"
        }
        for (index, site) in SteamAPISwap.sites(in: gameRoot).enumerated() {
            let cfg = gameRoot.resolvingSymlinksInPath().appendingPathComponent(site.path).deletingLastPathComponent().appendingPathComponent("steam_settings/configs.user.ini")
            let expected = #"local_save_path=C:\users\playport\AppData\Roaming\GSE Saves"#
            var state = "unavailable"
            if cfg.resolvingSymlinksInPath().standardizedFileURL == cfg.standardizedFileURL,
               let attr = try? fm.attributesOfItem(atPath: cfg.path), attr[.type] as? FileAttributeType == .typeRegular,
               (attr[.size] as? NSNumber)?.intValue ?? Int.max <= 16 << 10,
               let text = try? String(contentsOf: cfg, encoding: .utf8) {
                state = text.split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces) == expected }
                    ? "expected" : "missing or different"
            }
            report += "emulator-site-\(index): save-root=\(state)\n"
        }
        report += "native-engine-log: " + (nativeGameLogs(prefix: prefix, steamAppID: 1144400).isEmpty ? "missing, linked or over limit" : "included in report") + "\n"
        report += engineTimingOptions(gameRoot: gameRoot, native: locations[1].1)
        return report
    }

    /// Only bounded scalar engine options, including KiriKiri's escaped ASCII
    /// strings. Never include arbitrary config lines, paths or account values.
    private static func engineTimingOptions(gameRoot: URL, native: URL) -> String {
        var result = "Engine options (stored configuration; runtime scripts may override):\n"
        let keys = ["contfreq", "vsync", "waitvsync", "timerprec", "drawthread", "memusage", "gclim"]
        let fm = FileManager.default
        for (tag, base, name) in [("game", gameRoot.resolvingSymlinksInPath(), "senrenbanka.cf"),
                                   ("native", native, "senrenbanka.cfu")] {
            let names = (try? fm.contentsOfDirectory(atPath: base.path)) ?? []
            guard let spelling = names.first(where: { $0.lowercased() == name }) else { continue }
            let url = base.appendingPathComponent(spelling)
            guard url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL,
                  let attr = try? fm.attributesOfItem(atPath: url.path), attr[.type] as? FileAttributeType == .typeRegular,
                  (attr[.size] as? NSNumber)?.intValue ?? Int.max <= 16 << 10,
                  let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) ? .utf16 : .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, keys.contains(parts[0].lowercased()) else { continue }
                var value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"; "))
                guard value.count <= 64 else { continue }
                let escapes = try! NSRegularExpression(pattern: #"\\x([0-9a-fA-F]{2,4})"#)
                for match in escapes.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                    let raw = (value as NSString).substring(with: match.range(at: 1))
                    guard let code = UInt32(raw, radix: 16), code < 128, let scalar = UnicodeScalar(code),
                          let range = Range(match.range, in: value) else { continue }
                    value.replaceSubrange(range, with: String(scalar))
                }
                guard !value.isEmpty, value.count <= 16,
                      value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { continue }
                result += "\(tag)/\(parts[0].lowercased())=\(value)\n"
            }
        }
        return result
    }

    /// Fixed, public file names only. Hashes let a report establish the exact
    /// executable/runtime used without exporting game bytes, saves or credentials.
    public static func compatibilityFingerprints(gameRoot: URL, runtime: URL) -> String {
        var text = "Compatibility diagnostics: i386-exception-v6\nSHA256 and bytes; no file contents or private paths\n"
        let files = [
            ("game/SenrenBanka.exe", gameRoot.appendingPathComponent("SenrenBanka.exe")),
            ("game/SenrenBanka.exe.orig", gameRoot.appendingPathComponent("SenrenBanka.exe.orig")),
            ("game/SenrenBanka.cf", gameRoot.appendingPathComponent("SenrenBanka.cf")),
            ("game/steam_api.dll", gameRoot.appendingPathComponent("steam_api.dll")),
            ("runtime/i386/kernelbase.dll", runtime.appendingPathComponent("i386-windows/kernelbase.dll")),
            ("runtime/aarch64/xtajit.dll", runtime.appendingPathComponent("aarch64-windows/xtajit.dll")),
            ("runtime/aarch64/wow64.dll", runtime.appendingPathComponent("aarch64-windows/wow64.dll")),
            ("runtime/aarch64/wow64win.dll", runtime.appendingPathComponent("aarch64-windows/wow64win.dll")),
            ("runtime/arm64ec/xtajit64.dll", runtime.appendingPathComponent("arm64ec-windows/xtajit64.dll"))
        ]
        for (name, url) in files {
            guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attr[.type] as? FileAttributeType == .typeRegular,
                  let size = (attr[.size] as? NSNumber)?.intValue, size <= 16 << 20,
                  let bytes = try? Data(contentsOf: url) else {
                text += "\(name)\tmissing, linked or over limit\n"; continue
            }
            text += "\(name)\t\(bytes.count)\t\(SHA256Stream.hash(Array(bytes)).hex)\n"
        }
        return text
    }

    public static func endedBeforeDrawing(exitCode: UInt32, drewFrame: Bool, elapsed: TimeInterval,
                                         windowsMessage: String? = nil) -> Bool {
        !drewFrame && elapsed.isFinite && elapsed >= 0
            && (elapsed <= 10 || (elapsed <= 60 && windowsMessage?.isEmpty == false))
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

    /// The title writes script/storage exceptions outside its install folder.
    /// Include only that fixed diagnostic log, never save contents or INIs.
    public static func nativeGameLogs(prefix: URL, steamAppID: UInt32?) -> [URL] {
        guard steamAppID == 1144400 else { return [] }
        let url = prefix.resolvingSymlinksInPath()
            .appendingPathComponent("drive_c/users/playport/AppData/Roaming/YuzuSoft/SenrenBanka/krkr.console.log")
        guard url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL,
              let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
              attr[.type] as? FileAttributeType == .typeRegular,
              let size = (attr[.size] as? NSNumber)?.intValue, size > 0, size <= 2 << 20 else { return [] }
        return [url]
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

    /// Metadata records the game's API DLL architecture and backup layout.
    /// It does not claim SteamAPI_Init succeeded, and never reads account or ticket files.
    public static func steamFiles(in root: URL) -> String {
        let files = entries(in: root).filter {
            ["steam_api.dll", "steam_api64.dll", "steam_api.dll.orig", "steam_api64.dll.orig"].contains($0.url.lastPathComponent.lowercased())
        }
        var text = "Steam API file metadata (initialization not yet observed):\n"
        if files.isEmpty { text += "No Steam API DLL found in the bounded game-folder scan.\n" }
        for file in files {
            text += "\(file.relative)\t\(file.size) bytes\tmachine=\(peMachine(file.url).map { String(format: "0x%04X", $0) } ?? "unreadable PE")\n"
        }
        return text
    }

    private static func peMachine(_ url: URL) -> UInt16? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        do {
            guard let dos = try file.read(upToCount: 64), dos.count == 64, dos[0] == 0x4d, dos[1] == 0x5a else { return nil }
            let offset = dos[60..<64].enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << (8 * $1.offset)) }
            guard offset <= 16 << 20 else { return nil }
            try file.seek(toOffset: offset)
            guard let pe = try file.read(upToCount: 6), pe.count == 6, Array(pe.prefix(4)) == [0x50, 0x45, 0, 0] else { return nil }
            return UInt16(pe[4]) | (UInt16(pe[5]) << 8)
        } catch { return nil }
    }

    /// Inspect the exact bundle and Windows-directory codepage headers, without paths or contents.
    public static func codepageFiles(prefix: URL, runtime: URL) -> String {
        var text = "Windows codepage file probes (table ID, no private paths):\n"
        for dir in ["bundle", "system32", "syswow64", "sysarm64"] {
            for id in [932, 936, 950, 10000] {
                let base = dir == "bundle" ? runtime.appendingPathComponent("nls") : prefix.appendingPathComponent("drive_c/windows/" + dir)
                let url = base.appendingPathComponent("c_\(id).nls")
                guard let file = try? FileHandle(forReadingFrom: url) else {
                    text += "\(dir)/c_\(id).nls\tmissing or unreadable\n"; continue
                }
                let data = try? file.read(upToCount: 6)
                try? file.close()
                if let bytes = data, bytes.count == 6 {
                    let found = Int(bytes[2]) | (Int(bytes[3]) << 8)
                    text += "\(dir)/c_\(id).nls\ttable=\(found)\n"
                } else { text += "\(dir)/c_\(id).nls\ttruncated header\n" }
            }
        }
        return text
    }

    private struct Entry {
        var url: URL
        var relative: String
        var size: Int
    }

    private static func entries(in root: URL) -> [Entry] {
        let fm = FileManager.default
        let base = root.standardizedFileURL
        // URL resource-values enumeration returned nothing after Wine startup on
        // the phone while direct stat succeeded. Use the same direct metadata API.
        guard let attr = try? fm.attributesOfItem(atPath: base.path),
              attr[.type] as? FileAttributeType == .typeDirectory,
              let walk = fm.enumerator(atPath: base.path) else { return [] }
        var result: [Entry] = [], visited = 0
        for case let relative as String in walk {
            visited += 1
            if visited > 2048 { break }
            guard !relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }), walk.level <= 4 else {
                walk.skipDescendants(); continue
            }
            let url = base.appendingPathComponent(relative)
            guard let values = try? fm.attributesOfItem(atPath: url.path),
                  let type = values[.type] as? FileAttributeType else { walk.skipDescendants(); continue }
            if type == .typeSymbolicLink { walk.skipDescendants(); continue }
            guard type == .typeRegular else { continue }
            let name = relative.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
            result.append(Entry(url: url, relative: name, size: (values[.size] as? NSNumber)?.intValue ?? 0))
        }
        return result.sorted { $0.relative < $1.relative }
    }
}
