// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import PlayportKit
import SwiftUI
import WineHost

@MainActor
final class MemorySafetyWatch: ObservableObject {
    static let shared = MemorySafetyWatch()
    @Published private(set) var warning: String?
    private var task: Task<Void, Never>?
    private var reserve = MemorySafety.defaultMB
    private var lastDenials: UInt64 = 0

    nonisolated static var configuredMB: Int {
        let defaults = UserDefaults.standard
        return MemorySafety.margin(defaults.object(forKey: MemorySafety.preferenceKey) as? Int ?? MemorySafety.defaultMB)
    }

    nonisolated static var refusalDetail: String? {
        let count = wine_host_memory_denials()
        guard count > 0 else { return nil }
        return "本次因記憶體安全餘裕不足，已拒絕 \(count) 次新的記憶體配置（餘裕 \(configuredMB) MB）。可在設定調整；iOS 記憶體上限不變。"
    }

    func start() {
        stop()
        reserve = Self.configuredMB
        lastDenials = UInt64(wine_host_memory_denials())
        task = Task { @MainActor in
            var ticks = 0
            while !Task.isCancelled {
                let reading = MemoryLimit.read()
                let available = reading.effectiveMB.map { max(0, $0 - reading.footprintMB) }
                let denials = UInt64(wine_host_memory_denials())
                let rejected = denials > self.lastDenials
                let low = available.map { MemorySafety.shouldWarn(available: $0, margin: reserve) } ?? false
                let next: String? = rejected ? "記憶體安全餘裕不足，已拒絕新的記憶體配置。" :
                    low ? "記憶體餘裕提醒：剩餘約 \(((available ?? 0) / 50) * 50) MB，安全餘裕 \(reserve) MB。" : nil
                if next != warning { warning = next }
                // Keep safety checks at 1 Hz and refusal reports immediate,
                // but batch ordinary memory diagnostics into ten-second logs.
                if rejected || ticks % 10 == 0 {
                    let target = MemorySafety.targetMB(used: reading.footprintMB, limit: reading.effectiveMB, margin: reserve)
                    AppLog.append("memory-safety: used_mb=\(reading.footprintMB) compressed_original_mb=\(reading.compressedMB) target_mb=\(target) headroom_mb=\(reserve) available_mb=\(available.map(String.init) ?? "unknown") denied=\(denials)")
                }
                self.lastDenials = denials
                if ticks % 5 == 0, !InGameMenu.shared.isOpen, let report = PacedMetalLayer.healthReport() {
                    AppLog.append(report)
                }
                ticks += 1
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }
    func stop() { task?.cancel(); task = nil; warning = nil }
}

struct MemorySafetyBanner: View {
    @ObservedObject private var watch = MemorySafetyWatch.shared
    @AppStorage(MemorySafety.warningPreferenceKey) private var showWarnings = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if showWarnings, let warning = watch.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 8).padding(.horizontal, 24)
                    .transition(.opacity)
                    .accessibilityLabel(warning)
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.2), value: watch.warning)
        .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.2), value: showWarnings)
        .allowsHitTesting(false)
    }
}
