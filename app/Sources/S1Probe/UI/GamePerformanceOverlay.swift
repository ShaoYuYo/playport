// SPDX-License-Identifier: GPL-3.0-or-later
import HostIOKit
import SwiftUI

@MainActor
final class GamePerformanceStats: ObservableObject {
    static let shared = GamePerformanceStats()
    @Published private(set) var sample: FrameHealth.Sample?
    @Published private(set) var footprint: Int?
    func update(_ sample: FrameHealth.Sample?, footprint: Int) {
        self.sample = sample
        self.footprint = footprint
    }
}

/// Reuses health reporting: no display link, GPU readback, extra sampler or
/// per-frame SwiftUI publication. Five-second averages are labelled as such.
struct GamePerformanceOverlay: View {
    @ObservedObject private var menu = InGameMenu.shared
    @ObservedObject private var launch = TitleLaunch.shared
    @ObservedObject private var stats = GamePerformanceStats.shared
    @ObservedObject private var safe = WindowInsets.shared
    var body: some View {
        #if PLAYPORT_RELEASE
        if menu.overlay && !menu.isOpen && launch.acceptsMenu {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(stats.sample.map { String(format: "%.0f", $0.fps) } ?? "—")
                        .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("FPS · 平均").font(.system(size: 10, weight: .semibold)).foregroundStyle(PP.soft)
                }
                Text(stats.footprint.map { "RAM  \($0) MB" } ?? "RAM  —").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(PP.soft)
                if let sample = stats.sample {
                    Text(String(format: "最長間隔 %.0f ms", sample.maximumGapMS))
                        .font(.system(size: 10)).foregroundStyle(PP.muted)
                }
            }
            .foregroundStyle(PP.text).padding(12).ppOverlayPanel(cornerRadius: 16)
            .padding(.top, max(8, safe.insets.top + 8))
            .padding(.trailing, max(68, safe.insets.trailing + 68))
            .allowsHitTesting(false).accessibilityLabel("效能資訊，最近五秒平均")
        }
        #endif
    }
}
