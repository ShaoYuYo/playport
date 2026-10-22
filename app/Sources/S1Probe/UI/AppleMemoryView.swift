// SPDX-License-Identifier: GPL-3.0-or-later
import AppleAccountKit
import Foundation
import SteamClientKit
import SwiftUI

@MainActor
final class AppleMemoryModel: ObservableObject {
    static let shared = AppleMemoryModel()
    @Published var presented = false
    @Published private(set) var busy = false
    @Published private(set) var teams: [DeveloperTeam] = []
    @Published private(set) var app: DeveloperApp?
    @Published private(set) var team: DeveloperTeam?
    @Published private(set) var message = "請使用原側載工具所用的 Apple 帳號。"
    @Published private(set) var needsCode = false
    @Published var codeEntry = ""
    @Published private(set) var remoteEnabled: Bool?
    let bundleID = Bundle.main.bundleIdentifier ?? ""
    private let store = KeychainSecretStore(service: "dev.playport.apple-memory")
    private var client: AppleMemoryClient?
    private var job: Task<Void, Never>?
    private var verification: AppleVerificationCode?
    private var generation = 0
    func show() {
        guard !TitleLaunch.shared.running else { return }
        AppDelegate.allowsPortrait = true
        presented = true
    }
    private func saveIdentity(_ client: AppleMemoryClient) async {
        if let data = try? await client.identityRecord() { try? store.write("anisette-identity", Secret(Array(data))) }
    }
    func signIn(email: String, password: String) {
        guard presented, !busy else { return }
        generation += 1; let id = generation
        let record = (try? store.read("anisette-identity"))?.value.map { $0 }
        let client = AppleMemoryClient(identityRecord: record.map { Data($0) })
        let verification = AppleVerificationCode()
        self.verification = verification
        self.client = client; busy = true; message = "正在安全登入 Apple…"
        job = Task {
            defer { if id == generation { verification.cancel(); self.verification = nil; needsCode = false; busy = false; job = nil } }
            do {
                let values = try await client.signIn(email: email, password: password, verificationRequested: { sms in
                    await self.showCode(sms: sms, generation: id)
                }, verification: { _ in
                    try await verification.value()
                })
                await saveIdentity(client)
                guard id == generation, presented else { await client.forgetSession(); return }
                teams = values
                message = values.isEmpty ? "Apple 沒有傳回可使用的開發者團隊。" : "請選擇側載使用的團隊。"
            } catch {
                await saveIdentity(client)
                guard id == generation else { return }
                message = (error as? AppleProvisioningError)?.localizedDescription ?? "登入未完成，請檢查網路或重新嘗試。"
            }
        }
    }
    private func showCode(sms: Bool, generation id: Int) {
        guard id == generation, presented else { return }
        needsCode = true; codeEntry = ""
        message = sms ? "請輸入 Apple 傳送的六位簡訊驗證碼。" : "請先在受信任裝置允許登入，再輸入顯示的六位驗證碼。"
    }
    func submitCode(_ value: String) {
        guard needsCode, verification?.submit(value) == true else { return }
        needsCode = false; codeEntry = ""; message = "正在驗證…"
    }
    func choose(_ team: DeveloperTeam) {
        guard !busy, let client else { return }
        let id = generation
        busy = true; self.team = team; app = nil; remoteEnabled = nil
        message = "正在核對目前 App ID…"
        job = Task {
            defer { if id == generation { busy = false; job = nil } }
            do {
                let found = try await client.installedApp(team: team, bundleID: bundleID)
                let enabled = try await client.memoryEnabled(app: found, team: team)
                guard id == generation, presented, !Task.isCancelled else { return }
                app = found; remoteEnabled = enabled
                message = enabled ? "App ID 已啟用；實際 App 簽章狀態請見下方。" : "已核對 App ID，可加入 Increased Memory Limit。"
            } catch { guard id == generation else { return }; remoteEnabled = nil; message = (error as? AppleProvisioningError)?.localizedDescription ?? "無法讀取權限，未進行修改。" }
        }
    }
    func enable() {
        guard !busy, let client, let app, let team else { return }
        let id = generation
        busy = true; message = "正在保留現有權限並加入記憶體權限…"
        job = Task {
            defer { if id == generation { busy = false; job = nil } }
            do {
                try await client.enableMemory(app: app, team: team, installedBundleID: bundleID)
                guard id == generation, presented, !Task.isCancelled else { return }
                remoteEnabled = true
                message = "Apple 已確認 App ID 權限開啟。請用原側載工具重新簽署並覆蓋安裝 Playport，保留資料。"
            } catch { guard id == generation else { return }; remoteEnabled = nil; message = (error as? AppleProvisioningError)?.localizedDescription ?? "Apple 尚未確認更新成功，請重新整理。" }
        }
    }
    func close() {
        generation += 1; job?.cancel(); job = nil
        AppDelegate.allowsPortrait = false; codeEntry = ""
        verification?.cancel(); verification = nil
        if let client { Task { await client.forgetSession() } }
        client = nil; teams = []; app = nil; team = nil; remoteEnabled = nil
        needsCode = false; busy = false; presented = false
        message = "請使用原側載工具所用的 Apple 帳號。"
    }
}

struct AppleMemoryView: View {
    @ObservedObject private var model = AppleMemoryModel.shared
    @State private var email = ""
    @State private var password = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmsUpdate = false
    @FocusState private var field: Field?
    private enum Field { case email, password, code }
    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        activeStep.id("active-step")
                        installation
                    }
                    .frame(maxWidth: 640)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(PP.background)
                .task(id: "\(model.needsCode)-\(scenePhase)") {
                    guard model.needsCode, scenePhase == .active else { return }
                    scroll.scrollTo("active-step", anchor: .top)
                    // Wait for the former password keyboard's view to unmount.
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    if model.needsCode { field = .code }
                }
            }
            .navigationTitle(model.needsCode ? "Apple 驗證碼" : "增加記憶體權限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("關閉") { field = nil; model.close() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("收起鍵盤") { field = nil }
                    Spacer()
                    if model.needsCode { Button("驗證", action: verify).disabled(AppleVerificationCode.normalized(model.codeEntry) == nil) }
                }
            }
            .confirmationDialog("更新這個 Playport App ID 的權限？", isPresented: $confirmsUpdate) {
                Button("保留原權限並啟用") { model.enable() }
            } message: { Text("只加入 Increased Memory Limit；完成後仍需重新側載。") }
        }
        .preferredColorScheme(.dark).tint(PP.accent)
        // System authentication alerts may deactivate/rebuild this view. Only
        // the close button or the presentation owner's dismissal ends a session.
        .interactiveDismissDisabled(model.busy)
        .onDisappear { password = "" }
    }

    private var activeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(model.needsCode ? "雙重驗證" : model.teams.isEmpty ? "Apple 帳號" : "開發者團隊",
                  systemImage: model.needsCode ? "number.circle" : "person.crop.circle.badge.checkmark")
                .font(.title3.weight(.semibold))
            Text(model.message).font(.subheadline).foregroundStyle(PP.soft).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("apple-account-status")
            if model.needsCode {
                TextField("六位驗證碼", text: $model.codeEntry)
                    .textContentType(.oneTimeCode).keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center).focused($field, equals: .code)
                    .privacySensitive().accessibilityLabel("Apple 六位驗證碼")
                    .accessibilityIdentifier("apple-verification-code")
                    .padding(14).background(PP.background, in: RoundedRectangle(cornerRadius: 12))
                Button("驗證並繼續", action: verify)
                    .disabled(AppleVerificationCode.normalized(model.codeEntry) == nil)
                    .ppGlassButton(prominent: true).controlSize(.large)
                    .accessibilityIdentifier("apple-verification-submit")
                Text("可直接貼上或使用簡訊自動填寫；這是 Apple 驗證碼，無須匯入配對檔案。")
                    .font(.footnote).foregroundStyle(PP.muted)
            } else if model.teams.isEmpty && !model.busy {
                TextField("Apple 帳號", text: $email).textContentType(.username).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($field, equals: .email)
                    .submitLabel(.next).onSubmit { field = .password }
                    .padding(14).background(PP.background, in: RoundedRectangle(cornerRadius: 12))
                SecureField("密碼", text: $password).textContentType(.password).focused($field, equals: .password)
                    .submitLabel(.go).onSubmit(signIn)
                    .padding(14).background(PP.background, in: RoundedRectangle(cornerRadius: 12))
                Button("登入 Apple", action: signIn).disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                    .ppGlassButton(prominent: true).controlSize(.large)
                Text("密碼只用於 Apple SRP 驗證，不會儲存或寫入報告。裝置驗證服務 ani.sidestore.io 不會收到密碼或登入 token；裝置驗證資料保存在本機鑰匙圈。")
                    .font(.footnote).foregroundStyle(PP.muted)
            } else if !model.teams.isEmpty {
                ForEach(model.teams) { team in
                    Button { model.choose(team) } label: {
                        HStack { Text(team.name); Spacer(); Image(systemName: model.team?.id == team.id ? "checkmark.circle.fill" : "chevron.right") }
                            .padding(14).background(PP.background, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(model.busy)
                }
                if let app = model.app {
                    Text(app.bundleID).font(.footnote).textSelection(.enabled)
                    LabeledContent("Apple 端權限", value: model.remoteEnabled.map { $0 ? "已啟用" : "尚未啟用" } ?? "未確認")
                    Button("啟用 Increased Memory Limit") { confirmsUpdate = true }
                        .disabled(model.busy || model.remoteEnabled == true).ppGlassButton(prominent: true)
                    Button("重新整理") { if let team = model.team { model.choose(team) } }.disabled(model.busy).ppGlassButton()
                }
            }
            if model.busy && !model.needsCode { ProgressView().frame(maxWidth: .infinity) }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .ppOverlayPanel(cornerRadius: 20)
    }
    private var installation: some View {
        DisclosureGroup("目前安裝與生效方式") {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.bundleID).font(.footnote).textSelection(.enabled)
                LabeledContent("簽章記憶體權限", value: MemoryLimit.entitled.map { $0 ? "已具備" : "尚未具備" } ?? "未確認")
                Text("更新 Apple App ID 後，請用原側載工具重新簽署並覆蓋安裝，保留資料。這項權限無法增加實體 RAM。")
                    .font(.footnote).foregroundStyle(PP.muted)
            }.padding(.top, 12)
        }
    }
    private func signIn() {
        guard !model.busy, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else { return }
        field = nil; model.signIn(email: email, password: password); password = ""
    }
    private func verify() { model.submitCode(model.codeEntry); field = nil }
}
