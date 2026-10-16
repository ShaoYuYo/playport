// SPDX-License-Identifier: GPL-3.0-or-later
import PlayportKit
import SteamClientKit
import SwiftUI

/// A console home: large covers and ambient art. Focus never resizes a card.
struct HomeView: View {
    @ObservedObject var installs: Downloads
    @EnvironmentObject private var model: SteamAccountModel
    @ObservedObject private var library = LibraryModel.shared
    @ObservedObject private var nav = AppNavigation.shared
    @ObservedObject private var focus = PadFocus.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlighted: String?

    static func continueTitle(_ catalogued: [InstalledTitle]) -> InstalledTitle? {
        let titles = catalogued.filter(\.canPlay)
        return titles.filter { $0.lastPlayed != nil }.max { $0.lastPlayed! < $1.lastPlayed! } ?? titles.first
    }

    static func recentEntries(titles: [InstalledTitle], owned: [SteamGame], excluding heroID: String?) -> [LibraryEntry] {
        LibraryList.recent(LibraryList.entries(titles: titles, owned: owned), count: 10, excluding: heroID)
    }

    private var entries: [LibraryEntry] {
        let all = LibraryList.entries(titles: library.catalog.titles, owned: model.games)
        let hero = Self.continueTitle(library.catalog.titles).flatMap { title in all.first { $0.id == title.id } }
        return (hero.map { [$0] } ?? [])
            + Self.recentEntries(titles: library.catalog.titles, owned: model.games, excluding: hero?.id)
    }

    private var selected: LibraryEntry? { entries.first { $0.id == highlighted } ?? entries.first }

    static func loadArt(titles: [InstalledTitle], model: SteamAccountModel) async {
        let hero = continueTitle(titles)
        let recent = recentEntries(titles: titles, owned: model.games, excluding: nil)
        let wanted: [(UInt32?, ArtworkCache.Kind)] = [(hero?.appID, .hero)] + recent.prefix(5).map { ($0.appID, .capsule) }
        let art = wanted.compactMap { app, kind in model.games.first { $0.id == app }.map { ($0.info, kind) } }
        let loads: [Task<Void, Never>] = art.map { info, kind in
            Task<Void, Never> { @MainActor in _ = await model.image(info, kind) }
        }
        for load in loads { await load.value }
    }

    var body: some View {
        GeometryReader { viewport in
            let coverHeight = min(250, max(120, viewport.size.height - 78))
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Recent games").font(.system(size: 19, weight: .semibold))
                        Spacer()
                        if let job = installs.order.first {
                            Button { nav.show(.downloads) } label: {
                                Label(job.name, systemImage: "arrow.down.circle")
                                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    .frame(maxWidth: 190).padding(.horizontal, 10).padding(.vertical, 7)
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Downloads")
                        }
                    }
                    .foregroundStyle(PP.text).padding(.horizontal, 8)
                    if entries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "gamecontroller").font(.system(size: 36)).foregroundStyle(PP.accent)
                            Text("No games yet").font(.system(size: 25, weight: .semibold))
                            Text("Open Library to install or add a game.").font(.system(size: 15)).foregroundStyle(PP.soft)
                            Button { nav.show(.library) } label: { Label("Library", systemImage: "square.grid.2x2") }
                                .buttonStyle(.glassProminent).tint(PP.accent)
                        }
                        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 16) {
                                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                        cover(entry, height: coverHeight, first: index == 0)
                                    }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 7)
                            }
                            .onChange(of: focus.focused) { _, id in
                                guard let id, let entry = entries.first(where: { itemID($0) == id }) else { return }
                                highlighted = entry.id
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                            }
                        }
                    }
                }
                .padding(.top, 10)
            }
            .clipped()
        }
    }

    private func itemID(_ entry: LibraryEntry) -> String {
        entry.id == entries.first?.id ? "hero:\(entry.id)" : "home:\(entry.id)"
    }

    private func cover(_ entry: LibraryEntry, height: CGFloat, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GameArt(appID: entry.appID, name: entry.name, kind: .capsule,
                    titleID: entry.installed ? entry.id : nil, storeKey: entry.key)
                .frame(width: height * 2 / 3, height: height)
                .overlay(alignment: .bottomLeading) {
                    if first {
                        Text(entry.installed ? "Continue" : "Open")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                .padItem(itemID(entry), hint: "Open", cornerRadius: 8) { nav.openGame(.title(entry.id)) }
            Text(entry.name).font(.system(size: 13, weight: .medium)).foregroundStyle(PP.text).lineLimit(1)
                .frame(width: height * 2 / 3, alignment: .leading)
        }
    }
}

struct ProgressBar: View {
    let fraction: Double
    var height: CGFloat = 6
    var track: Color = PP.line
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(PP.progress).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }
}
