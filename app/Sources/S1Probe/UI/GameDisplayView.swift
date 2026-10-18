// SPDX-License-Identifier: GPL-3.0-or-later
import AVFAudio
import HostIOKit
import PlayportKit
import SwiftUI
import UIKit

struct GameDisplayView: View {
    @ObservedObject private var settings = LaunchSettingsStore.shared
    @ObservedObject private var launch = TitleLaunch.shared
    @Environment(\.dismiss) private var dismiss
    @State private var fps = TitleScreen.frameLimit
    @AppStorage(GameViewport.edgeToEdgeKey) private var edgeToEdge = true
    @AppStorage(MemorySafety.warningPreferenceKey) private var showMemoryWarnings = true
    @AppStorage(EdgeMenuVisibility.preferenceKey) private var menuAutoHide = true

    private var own: LaunchSettings {
        launch.titleID.map { settings.settings(for: $0) } ?? LaunchSettings()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("顯示") {
                    Button("平衡 · 720p / 60 FPS") { setPreset(fps: 60) }
                    Button("省電 · 720p / 30 FPS") { setPreset(fps: 30) }
                    Text("想降低發熱並保留流暢度，先用平衡模式；需要更長續航時選省電。FPS 立即套用，解析度在下次啟動生效。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("畫面延伸至螢幕邊緣", isOn: $edgeToEdge)
                    Text("立即套用。畫面使用完整螢幕範圍，維持比例；按鈕仍避開鏡頭與手勢區。遊戲本身的黑邊可能保留。")
                        .font(.footnote).foregroundStyle(.secondary)
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
                Section("遊戲提醒") {
                    Toggle("自動隱藏設定按鈕", isOn: $menuAutoHide)
                    Text("約 2.5 秒後淡出。點右上角原位置一下即可開啟；滑鼠移到按鈕也能顯示。位置固定在避開鏡頭的安全邊緣。配置按鍵與使用 VoiceOver 時保持顯示。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("顯示記憶體餘裕提醒", isOn: $showMemoryWarnings)
                    Text("關閉後不顯示遊戲上方的 RAM 提醒；記憶體安全檢查與失敗紀錄仍然保留。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let sample = PacedMetalLayer.latestHealth {
                    Section("開啟選單前的呈現紀錄") {
                        LabeledContent("實際 FPS", value: String(format: "%.1f", sample.fps))
                        LabeledContent("遊戲要求影格間隔", value: String(format: "%.1f ms", sample.averageRequestGapMS))
                        LabeledContent("遊戲與提交間隔", value: String(format: "%.1f ms", sample.averageProducerGapMS))
                        LabeledContent("等待顯示影像", value: String(format: "%.1f ms", sample.averageDrawableWaitMS))
                        LabeledContent("啟動器限幀等待", value: String(format: "%.1f ms", sample.averagePacerWaitMS))
                        if let cpu = sample.processCPUPercent {
                            LabeledContent("App CPU 用量", value: String(format: "%.0f%%", cpu))
                        }
                        Text("這是遊戲暫停前最近一段紀錄；選單期間不計入。CPU 為所有執行緒合計，100% 代表一個核心滿載。遊戲與提交間隔也包含腳本及其他等待，不能當成純 CPU 時間。千戀萬花即使選不限，也會避免以無限次連續更新讓 CPU 空轉；明確的啟動參數與遊戲腳本仍可覆寫。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
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
