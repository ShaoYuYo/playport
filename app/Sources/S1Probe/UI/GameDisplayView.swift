// SPDX-License-Identifier: GPL-3.0-or-later
import AVFAudio
import PlayportKit
import SwiftUI
import UIKit

struct GameDisplayView: View {
    @ObservedObject private var settings = LaunchSettingsStore.shared
    @ObservedObject private var launch = TitleLaunch.shared
    @Environment(\.dismiss) private var dismiss
    @State private var fps = TitleScreen.frameLimit

    private var own: LaunchSettings {
        launch.titleID.map { settings.settings(for: $0) } ?? LaunchSettings()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("顯示") {
                    Button("順暢模式 · 720p / 60 FPS") { setPreset(fps: 60) }
                    Button("低負載模式 · 720p / 30 FPS") { setPreset(fps: 30) }
                    LabeledContent("裝置原生", value: LaunchSettingsText.screen("native"))
                    LabeledContent("本次遊戲螢幕", value: TitleScreen.configuredSize)
                    LabeledContent("遊戲呈現影像", value: PacedMetalLayer.lastPresented.map { "\($0.width)×\($0.height)" } ?? "尚無影像")
                    Picker("解析度（下次啟動）", selection: Binding(
                        get: { own.screen ?? settings.displayDefaults.screen ?? "native" },
                        set: { screen in
                            if let id = launch.titleID { settings.setDisplay(for: id, screen: screen) }
                        })) {
                        ForEach(LaunchSettingsText.screens, id: \.self) { Text(LaunchSettingsText.screen($0)).tag($0) }
                    }
                    .disabled(launch.titleID == nil)
                    Picker("FPS 上限（立即套用）", selection: $fps) {
                        ForEach(LaunchSettingsText.frameLimits, id: \.self) { Text("\($0) FPS").tag($0) }
                        Text("不限").tag(0)
                        if fps > 0 && !LaunchSettingsText.frameLimits.contains(fps) { Text("\(fps) FPS").tag(fps) }
                    }
                    .onChange(of: fps) { _, value in
                        TitleScreen.setFrameLimit(value)
                        if let id = launch.titleID { settings.setDisplay(for: id, fps: value) }
                        HostIO.log("display: frame limit \(TitleScreen.frameLimit), panel \(UIScreen.main.maximumFramesPerSecond) Hz")
                    }
                    Text("保持遊戲原本比例，不拉伸畫面。遊戲可能使用固定解析度素材或自己的幀率上限；提高輸出解析度與上限不保證提高實際 FPS。若負載過高，改用較低解析度。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("聲音 · 保留原品質") {
                    LabeledContent("混音傳輸", value: "未壓縮 PCM · 32-bit float")
                    LabeledContent("裝置輸出", value: Self.audioDescription)
                    LabeledContent("系統音量", value: "\(Int(AVAudioSession.sharedInstance().outputVolume * 100))%")
                    Text("不重新編碼遊戲音訊、不降低取樣率。系統會依輸出裝置進行必要的格式轉換；藍牙音訊編碼由 iOS 與耳機決定。選單暫停遊戲及聲音，返回遊戲後恢復。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("畫面與聲音")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }

    private static var audioDescription: String {
        let s = AVAudioSession.sharedInstance()
        return "\(Int(s.sampleRate)) Hz · \(s.outputNumberOfChannels) 聲道"
    }

    private func setPreset(fps: Int) {
        if let id = launch.titleID {
            settings.setDisplay(for: id, screen: launch.appID == 1144400 ? "1280x720" : "720", fps: fps)
        }
        TitleScreen.setFrameLimit(fps)
        self.fps = fps
    }
}
