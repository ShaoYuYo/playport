// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation
import PlayportKit

/// Main-actor exclusion with TitleLaunch.start: an idle cache clean cannot
/// overlap the next game's startup. It remains held across the detached I/O.
@MainActor
final class StorageMaintenance: ObservableObject {
    static let shared = StorageMaintenance()
    @Published private(set) var busy = false
    @Published private(set) var status = ""
    private var cleanup: StorageCleanup {
        StorageCleanup(container: WineHostRuntime.documents.deletingLastPathComponent())
    }

    func clean() {
        guard !busy else { return }
        busy = true
        let gameRunning = TitleLaunch.shared.running
        let cleaner = cleanup
        Task {
            let result = await Task.detached(priority: .utility) {
                cleaner.run(gameRunning: gameRunning, remove: true)
            }.value
            status = "已清除 \(result.files) 個快取檔案，合計 \(ByteCount.format(result.bytes))。"
                + (gameRunning ? "遊戲執行中，保留使用中的圖形與轉譯快取。" : "圖形快取會在需要時重建，首次載入可能較慢。")
                + (result.failed > 0 ? "\(result.failed) 個檔案暫時無法清除。" : "")
                + (result.limited ? "本次已達掃描上限，可再次清理。" : "")
            WineHostRuntime.appendLog("storage-cleanup-v1: files=\(result.files) logical_bytes=\(result.bytes) failed=\(result.failed) limited=\(result.limited) game_running=\(gameRunning)")
            busy = false
        }
    }
}
