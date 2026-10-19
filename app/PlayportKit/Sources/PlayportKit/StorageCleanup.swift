// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Only rebuildable, app-owned locations. Never enumerate Games, saves,
/// Cloud Backups, account state, .orig publisher files or the Wine temp tree.
public struct StorageCleanup: Sendable {
    public struct Result: Sendable {
        public var bytes: UInt64 = 0
        public var files: Int = 0
        public var failed: Int = 0
        public var limited = false
    }
    private let container: URL
    public init(container: URL) { self.container = container.resolvingSymlinksInPath().standardizedFileURL }

    /// Runtime caches are pinned for the entire launch, including preparation
    /// and pauses. In a play only old exported reports can be removed.
    public func run(gameRunning: Bool, remove: Bool = false, now: Date = Date(),
                    fileLimit: Int = 20_000) -> Result {
        let fm = FileManager.default
        let boundary = container.path + "/"
        var result = Result(), visited = 0
        let reports = container.appendingPathComponent("tmp/Report a problem")
        var roots = [reports]
        if !gameRunning {
            roots += ["Library/Caches/dxmt", "Library/Caches/kosmickrisp",
                      "Documents/prefix/drive_c/users/playport/AppData/Local/fex-emu/DiskCache"]
                .map { container.appendingPathComponent($0) }
        }
        // Resolve every ancestor, too. A cache directory replaced with a link
        // must never allow deletion in another part of the container.
        func safe(_ url: URL) -> Bool {
            url.standardizedFileURL.path.hasPrefix(boundary) &&
                url.resolvingSymlinksInPath().standardizedFileURL.path == url.standardizedFileURL.path
        }
        for root in roots {
            guard safe(root),
                  (try? fm.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType) == .typeDirectory,
                  let walk = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walk {
                visited += 1
                guard visited <= max(0, fileLimit) else { result.limited = true; return result }
                guard safe(url), let attributes = try? fm.attributesOfItem(atPath: url.path) else {
                    walk.skipDescendants(); continue
                }
                if attributes[.type] as? FileAttributeType == .typeDirectory { continue }
                guard attributes[.type] as? FileAttributeType == .typeRegular else { continue }
                if root == reports {
                    // Keep recent exports for sharing. No arbitrary temp files:
                    // pairing imports, downloads and active reports stay put.
                    guard url.pathExtension.lowercased() == "zip",
                          let date = attributes[.modificationDate] as? Date,
                          now.timeIntervalSince(date) > 86_400 else { continue }
                }
                if remove {
                    do { try fm.removeItem(at: url) } catch { result.failed += 1; continue }
                }
                result.files += 1
                result.bytes += (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            }
        }
        return result
    }
}
