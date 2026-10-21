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
    @Published private(set) var remoteEnabled: Bool?
    let bundleID = Bundle.main.bundleIdentifier ?? ""
    private let store = KeychainSecretStore(service: "dev.playport.apple-memory")
    private var client: AppleMemoryClient?
    private var job: Task<Void, Never>?
    private var codeWaiter: CheckedContinuation<String, Error>?
    private var generation = 0
    func show() {
        guard !TitleLaunch.shared.running else { return }
        presented = true
    }
    private func saveIdentity(_ client: AppleMemoryClient) async {
        if let data = try? await client.identityRecord() { try? store.write("anisette-identity", Secret(Array(data))) }
    }
    func signIn(email: String, password: String) {
        guard !busy else { return }
        generation += 1; let id = generation
        let record = (try? store.read("anisette-identity"))?.value.map { $0 }
        let client = AppleMemoryClient(identityRecord: record.map { Data($0) })
        self.client = client; busy = true; message = "正在安全登入 Apple…"
        job = Task {
            defer { if id == generation { busy = false; job = nil } }
            do {
                let values = try await client.signIn(email: email, password: password) { sms in
                    try await self.code(sms: sms)
                }
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
    private func code(sms: Bool) async throws -> String {
        guard presented, !Task.isCancelled else { throw AppleProvisioningError.cancelled }
        needsCode = true; message = sms ? "請輸入 Apple 傳送的六位簡訊驗證碼。" : "請輸入受信任裝置顯示的六位驗證碼。"
        return try await withCheckedThrowingContinuation { codeWaiter = $0 }
    }
    func submitCode(_ value: String) {
        guard value.count == 6, value.allSatisfy(\.isNumber) else { return }
        let waiter = codeWaiter; codeWaiter = nil; needsCode = false
        message = "正在驗證…"; waiter?.resume(returning: value)
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
        let waiter = codeWaiter; codeWaiter = nil; waiter?.resume(throwing: AppleProvisioningError.cancelled)
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
    @State private var code = ""
    @State private var confirmsUpdate = false
    var body: some View {
        NavigationStack {
            Form {
                Section("目前安裝") {
                    LabeledContent("App ID", value: model.bundleID).textSelection(.enabled)
                    LabeledContent("簽章記憶體權限", value: MemoryLimit.entitled.map { $0 ? "已具備" : "尚未具備" } ?? "未確認")
                    Text("此功能會更新 Apple 帳號中的 App ID；仍須重新簽署並覆蓋安裝才會生效，無法增加實體 RAM。")
                }
                if model.teams.isEmpty && !model.needsCode {
                    Section("內置 Apple 登入") {
                        TextField("Apple 帳號", text: $email).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("密碼", text: $password).textContentType(.password)
                        Text("密碼只用於與 Apple 進行 SRP 驗證，不會儲存或寫入報告。驗證資料服務使用 ani.sidestore.io，不會收到 Apple 密碼或登入 token；其裝置驗證資料保存在本機鑰匙圈。")
                            .font(.footnote)
                        Button("登入 Apple") { model.signIn(email: email, password: password); password = "" }
                            .disabled(model.busy || email.isEmpty || password.isEmpty)
                    }
                }
                if model.needsCode {
                    Section("雙重驗證") {
                        TextField("六位驗證碼", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                        Button("驗證") { model.submitCode(code); code = "" }.disabled(code.count != 6)
                    }
                }
                if !model.teams.isEmpty {
                    Section("開發者團隊") {
                        ForEach(model.teams) { team in
                            Button { model.choose(team) } label: {
                                HStack { Text(team.name); Spacer(); if model.team?.id == team.id { Image(systemName: "checkmark") } }
                            }.disabled(model.busy)
                        }
                    }
                }
                if let app = model.app {
                    Section("已核對的 Playport App ID") {
                        Text(app.bundleID).textSelection(.enabled)
                        LabeledContent("Apple 端權限", value: model.remoteEnabled.map { $0 ? "已啟用" : "尚未啟用" } ?? "未確認")
                        Button("啟用 Increased Memory Limit") { confirmsUpdate = true }
                            .disabled(model.busy || model.remoteEnabled == true)
                        Button("重新整理") { if let team = model.team { model.choose(team) } }.disabled(model.busy)
                    }
                }
                Section {
                    if model.busy { ProgressView() }
                    Text(model.message)
                }
            }
            .navigationTitle("增加記憶體權限")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { model.close() } } }
            .confirmationDialog("更新這個 Playport App ID 的權限？", isPresented: $confirmsUpdate) {
                Button("保留原權限並啟用") { model.enable() }
            } message: { Text("只加入 Increased Memory Limit，不刪除其他權限；完成後仍需重新側載。") }
        }
        .onDisappear { password = ""; code = ""; model.close() }
    }
}
