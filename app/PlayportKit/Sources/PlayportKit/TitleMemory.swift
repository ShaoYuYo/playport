// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Measured title-specific reductions. Other games keep their existing budget.
/// The pool is fixed before JIT activation; it cannot grow during a play.
public struct TitleMemory: Equatable, Sendable {
    public static let preferenceKey = "titleMemoryEconomy"
    public let poolMB: Int?
    public let active: Bool

    public init(steamAppID: UInt32?, i386: Bool, enabled: Bool) {
        active = enabled && i386 && steamAppID == 1144400
        // Supplied startup report: head 26 + tail 33 MiB, no pool refusals.
        // Keep room for the normal 128 MiB translation buffer and later images.
        poolMB = active ? 256 : nil
    }

    public func config(over base: [String: String]) -> [String: String] {
        guard active else { return base }
        var result = base
        // All Wine processor queries and both PEBs use this existing setting.
        // A smaller automatic worker fleet also needs fewer FEX per-thread heaps.
        if result["cpu-count"] == nil { result["cpu-count"] = "2" }
        return result
    }

    public func arguments(over base: [String]) -> [String] {
        guard active else { return base }
        var result = base
        // The old low mode tells KiriKiri it has zero physical memory and
        // disables its segment/layer caches. Keep the bounded worker fleet,
        // but allow the engine's normal cache policy to reuse decoded scenes.
        for (key, value) in [("memusage", "normal"), ("gclim", "64"), ("drawthread", "2")] {
            let option = "-" + key
            if !base.contains(where: { $0.lowercased() == option || $0.lowercased().hasPrefix(option + "=") }) {
                result.append(option + "=" + value)
            }
        }
        return result
    }
}

/// Bounded OS file-cache warmup before guest threads start. This does not
/// retain decoded assets or compile game scripts/shaders outside their engine.
public enum TitleAssetWarmup {
    public struct Result: Sendable { public let files: Int; public let bytes: Int; public let seconds: Double }

    public static func run(in root: URL, byteLimit: Int = 8 << 20, seconds: Double = 0.25) -> Result {
        let began = ProcessInfo.processInfo.systemUptime
        let fm = FileManager.default
        var files = 0, bytes = 0
        func regular(_ url: URL) -> Bool {
            (try? fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular
        }
        var candidates: [URL] = []
        // Do not traverse links, recurse through the install or warm whole XP3s.
        for dir in [root, root.appendingPathComponent("plugin")] {
            guard ProcessInfo.processInfo.systemUptime - began < seconds else { break }
            guard (try? fm.attributesOfItem(atPath: dir.path)[.type] as? FileAttributeType) == .typeDirectory else { continue }
            let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted().prefix(2048)
            candidates += names.map { dir.appendingPathComponent($0) }.filter {
                ["exe", "dll", "xp3"].contains($0.pathExtension.lowercased())
            }
        }
        for url in candidates.prefix(64) {
            guard bytes < max(0, byteLimit), ProcessInfo.processInfo.systemUptime - began < seconds else { break }
            guard regular(url) else { continue }
            guard ProcessInfo.processInfo.systemUptime - began < seconds,
                  let file = try? FileHandle(forReadingFrom: url) else { break }
            defer { try? file.close() }
            let cap = min(byteLimit - bytes, url.pathExtension.lowercased() == "xp3" ? 16 << 10 : 512 << 10)
            guard cap > 0, let header = try? file.read(upToCount: cap) else { continue }
            bytes += header.count; files += 1
            // XP3 index offset is public container metadata. Warm only a small
            // index prefix; never unpack protected indexes or guess scene data.
            if header.count >= 19, Array(header.prefix(11)) == [0x58,0x50,0x33,0x0d,0x0a,0x20,0x0a,0x1a,0x8b,0x67,0x01],
               bytes < byteLimit, ProcessInfo.processInfo.systemUptime - began < seconds {
                let offset = header[11..<19].enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << (8 * $1.offset)) }
                if let size = try? file.seekToEnd(), offset >= UInt64(header.count), offset < size {
                    try? file.seek(toOffset: offset)
                    if let index = try? file.read(upToCount: min(128 << 10, byteLimit - bytes)) { bytes += index.count }
                }
            }
        }
        return Result(files: files, bytes: bytes, seconds: ProcessInfo.processInfo.systemUptime - began)
    }
}
