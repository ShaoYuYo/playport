// SPDX-License-Identifier: GPL-3.0-or-later
// The Cloud save conflict screen (CloudConflict.dc.html): a game whose saves
// changed on this phone and on Steam Cloud since the last sync asks once
// which side to keep, for all its conflicting files (PlayportKit CloudSides).
// A keeps the phone's, X keeps Steam's: one SteamService.syncCloud(resolve:)
// call settles every file the same way (SteamService.resolveAll), and the side
// not picked is backed up for 30 days (Cloud.Backups, pruned by LibraryModel).
// B, Decide later, closes it and the game does not start.
// Y explicitly starts Senren from verified phone saves with cloud choices
// kept unresolved; this does not count as a completed sync.
//
// Play asks it first (LibraryModel.play, `cloudGate`) and starts the game once
// the choice is settled; Game options' Cloud saves row asks it without a Play.

import HostIOKit
import PlayportKit
import SteamClientKit
import SwiftUI

@MainActor
final class CloudConflictSession: ObservableObject {
    let titleID: String
    let appID: UInt32
    let name: String
    let conflicts: [SteamService.CloudConflict]
    let sides: CloudSides
    /// Play the game once the choice is settled.
    let thenPlay: Bool
    /// Played on this phone (the catalogue's total), for the phone's card.
    let playSeconds: TimeInterval?
    @Published private(set) var settling: SteamService.CloudChoice?
    @Published private(set) var error: String?

    init(titleID: String, appID: UInt32, name: String, conflicts: [SteamService.CloudConflict], thenPlay: Bool, playSeconds: TimeInterval?) {
        self.titleID = titleID
        self.appID = appID
        self.name = name
        self.conflicts = conflicts
        sides = CloudSides(conflicts)
        self.thenPlay = thenPlay
        self.playSeconds = playSeconds
    }

    func press(_ b: NavButton) {
        guard settling == nil else { return }
        switch b {
        case .a: keep(.phone)
        case .x: keep(.steam)
        case .y: playPhoneOffline()
        case .b: decideLater()
        default: break
        }
    }

    var canPlayPhoneOffline: Bool {
        thenPlay && appID == 1144400
    }

    func playPhoneOffline() {
        guard canPlayPhoneOffline, settling == nil else { return }
        settling = .phone
        error = nil
        if case .cloud(let s) = PadModal.shared.content, s === self { PadModal.shared.close() }
        Task {
            defer { settling = nil }
            do {
                if try await LibraryModel.shared.play(titleID, phoneCloudOffline: true) != true,
                   !TitleLaunch.shared.running, !PadModal.shared.isUp {
                    AppNavigation.shared.openTitle(titleID)
                }
            } catch {
                LibraryModel.log("play phone offline refused: \(error)")
                self.error = (error as? SteamCloudLaunchError)?.reason ?? "暫時無法準備遊戲，請稍後重試。"
                if !TitleLaunch.shared.running, !PadModal.shared.isUp { PadModal.shared.cloudConflict(self) }
            }
        }
    }

    func decideLater() {
        guard settling == nil else { return }
        LibraryModel.log("cloud: \(titleID): decide later; \(conflicts.count) conflict(s) stay"
                         + (thenPlay ? " and the game does not start" : ""))
        PadModal.shared.close()
    }

    func keep(_ side: SteamService.CloudChoice) {
        guard settling == nil, let steam = SteamAccountModel.current else { return }
        settling = side
        error = nil
        LibraryModel.log("cloud: \(titleID): keep \(side == .phone ? "this phone's" : "Steam Cloud's") saves for \(conflicts.count) file(s)")
        Task {
            await steam.syncCloud(appID, resolve: SteamService.resolveAll(conflicts, side))
            settling = nil
            let left = steam.cloud[appID]?.conflicts ?? conflicts
            if case .signedIn = steam.state {
                if let e = steam.cloudErrors[appID] {
                    error = "雲端同步未完成：\(e)。" + (canPlayPhoneOffline ? "可重試，或使用手機存檔離線啟動。" : "請重試或稍後再選。")
                } else if !left.isEmpty {
                    error = "仍有 \(left.count) 個檔案需要選擇版本，請重試或稍後再選。"
                }
            } else {
                error = "需要登入 Steam 才能完成同步。可登入後重試，或稍後再選。"
            }
            guard error == nil else {
                LibraryModel.log("cloud: \(titleID): not settled: \(error!)")
                return
            }
            LibraryModel.log("cloud: \(titleID): settled" + (thenPlay ? "; starting the game" : ""))
            if case .cloud(let s) = PadModal.shared.content, s === self { PadModal.shared.close() }
            guard thenPlay else { return }
            do {
                if try await LibraryModel.shared.play(titleID) != true, !TitleLaunch.shared.running, !PadModal.shared.isUp {
                    AppNavigation.shared.openTitle(titleID)
                }
            } catch {
                LibraryModel.log("play \(titleID) refused: \(error)")
                self.error = (error as? SteamCloudLaunchError)?.reason ?? "暫時無法準備遊戲，請稍後重試。"
                if !TitleLaunch.shared.running, !PadModal.shared.isUp { PadModal.shared.cloudConflict(self) }
            }
        }
    }
}

struct CloudConflictView: View {
    @ObservedObject var session: CloudConflictSession

    var body: some View {
        ZStack {
            // The design's own screen, not a scrim: the page and its footer do not show through.
            Color.black.opacity(0.38).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("選擇 \(session.name) 的存檔版本").font(PP.display(24)).lineLimit(2)
                Text("兩邊的存檔版本不同。選 Steam Cloud 會恢復整組雲端檔案；被取代的內容會保留備份 30 天。")
                    .font(.system(size: 13)).foregroundStyle(PP.muted).lineSpacing(2).padding(.top, -6)
                    .fixedSize(horizontal: false, vertical: true)
                if recovered {
                    Text("手機已放入所選備份。選「手機（已恢復備份）」才會將它同步回 Steam；選 Steam Cloud 會再次以現有雲端內容替換它。")
                        .font(.system(size: 13)).foregroundStyle(PP.accent).fixedSize(horizontal: false, vertical: true)
                } else if session.conflicts.contains(where: { $0.localCopiesDiffer == true }) {
                    Text("手機的本機與 Steam 儲存區也有不同內容。「手機」使用遊戲本機資料夾的版本；其他版本會先備份。若要載入電腦上的進度，請選 Steam Cloud。")
                        .font(.system(size: 13)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 14) {
                    card(.phone, heading: recovered ? "手機（已恢復備份）" : "手機", time: session.sides.phone.newest, line: phoneLine, button: .a)
                    card(.steam, heading: "Steam Cloud", time: session.sides.steam.newest, line: steamLine, button: .x)
                }
                if let e = session.error {
                    Text(e).font(.system(size: 12)).foregroundStyle(Color(hex: 0xFF9A6B))
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(width: 600)
            .ppGlass(cornerRadius: 22, interactive: false)
            .padding(.bottom, 20)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if session.canPlayPhoneOffline {
                        PadModalHint(button: .y, label: "使用手機存檔離線啟動") { session.press(.y) }
                    }
                    PadModalHint(button: .b, label: session.thenPlay ? "稍後再選（暫不啟動）" : "稍後再選") {
                        session.press(.b)
                    }
                }
                .padding(.horizontal, 36)
                .frame(height: 36)
            }
        }
        .foregroundStyle(PP.text)
        .accessibilityIdentifier("cloud-conflict")
    }

    private var recovered: Bool { session.conflicts.contains { $0.recoveredBackup == true } }

    private var phoneLine: String {
        let s = session.sides.phone
        if s.files == 0 { return "No save on this phone" }
        if recovered { return files(s) }
        return session.playSeconds.map { "Played \(PlayTime.format($0)) here" } ?? files(s)
    }

    private var steamLine: String {
        let s = session.sides.steam
        return s.files == 0 ? "Nothing on Steam yet" : files(s)
    }

    private func files(_ s: CloudSides.Side) -> String {
        "\(s.files) file\(s.files == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: Int64(s.bytes), countStyle: .file))"
    }

    private func when(_ d: Date?) -> String {
        guard let d else { return "—" }
        let time = d.formatted(date: .omitted, time: .shortened)
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today, \(time)" }
        if cal.isDateInYesterday(d) { return "Yesterday, \(time)" }
        return d.formatted(.dateTime.day().month(.abbreviated)) + ", \(time)"
    }

    /// One side: the ring on the phone's (A), as the design draws it.
    private func card(_ side: SteamService.CloudChoice, heading: String, time: Date?, line: String, button: NavButton) -> some View {
        let busy = session.settling == side
        return Button { session.press(button) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(heading.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.1).foregroundStyle(PP.muted)
                Text(when(time)).font(PP.display(22))
                Text(line).font(.system(size: 13)).foregroundStyle(PP.soft)
                HStack(spacing: 6) {
                    PadGlyph(button: button)
                    Text(busy ? "正在同步…" : "使用這個版本").font(.system(size: 13))
                    if busy { ProgressView().scaleEffect(0.6).tint(PP.text) }
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .ppGlass(cornerRadius: 14, tint: side == .phone ? PP.accent.opacity(0.12) : nil)
            .overlay {
                if side == .phone {
                    RoundedRectangle(cornerRadius: 17).stroke(PP.accent, lineWidth: 3).padding(-3)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(session.settling != nil && !busy ? 0.5 : 1)
        .accessibilityIdentifier("cloud-keep-\(side.rawValue)")
    }
}
