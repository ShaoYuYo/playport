// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Publisher-signed files transformed by launch preparation. Only Win32
/// read-only data opens use these originals; NT image loads keep the runnable
/// image. Signature validation remains the game's own, against original bytes.
public enum SignedOriginals {
    public static let environmentKey = "PLAYPORT_ORIGINAL_READBACK"

    public static func paths(in root: URL, selectedExecutable: URL, windowsExecutable: String) -> [String] {
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let selected = selectedExecutable.resolvingSymlinksInPath().standardizedFileURL.path
        guard selected.hasPrefix(base.path + "/") else { return [] }
        let relative = String(selected.dropFirst(base.path.count + 1)).split(separator: "/").map(String.init)
        let dos = windowsExecutable.replacingOccurrences(of: "/", with: "\\").split(separator: "\\").map(String.init)
        guard dos.first?.lowercased() == "c:", dos.count > relative.count,
              dos.suffix(relative.count).map({ $0.lowercased() }) == relative.map({ $0.lowercased() }) else { return [] }
        let windowsRoot = dos.dropLast(relative.count).joined(separator: "\\")
        let files = TitleInstaller.regularFiles(under: base)
        let names = Set(files)
        let chosen = relative.joined(separator: "/")
        var ordered = files.sorted()
        if let index = ordered.firstIndex(of: chosen) {
            ordered.remove(at: index)
            ordered.insert(chosen, at: 0)
        }
        var result: [String] = []
        for file in ordered {
            let lower = file.lowercased()
            guard lower.hasSuffix(".exe") || ["steam_api.dll", "steam_api64.dll"].contains((lower as NSString).lastPathComponent),
                  names.contains(file + ".orig"), names.contains(file + ".sig"),
                  !file.contains("\n"), !file.contains("\r"), !file.contains("\\"),
                  regular(base.appendingPathComponent(file), limit: 256 << 20),
                  regular(base.appendingPathComponent(file + ".orig"), limit: 256 << 20),
                  regular(base.appendingPathComponent(file + ".sig"), limit: 64 << 10) else { continue }
            let path = windowsRoot + "\\" + file.replacingOccurrences(of: "/", with: "\\")
            let value = (result + [path]).joined(separator: "\n")
            // WineHost's title request caps each UTF-8 KEY=VALUE entry below
            // 4096 bytes. Respect that transport as well as the PE reader cap.
            guard result.count < 32, value.utf16.count < 8191,
                  environmentKey.utf8.count + 1 + value.utf8.count < 4096 else { break }
            result.append(path)
        }
        return result
    }

    private static func regular(_ url: URL, limit: Int) -> Bool {
        guard url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let bytes = attributes[.size] as? NSNumber else { return false }
        return bytes.int64Value > 0 && bytes.int64Value <= limit
    }
}
