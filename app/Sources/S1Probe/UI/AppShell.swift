// SPDX-License-Identifier: GPL-3.0-or-later
// The product UI's frame (docs/design/2026-09-28-gamepad-ui/), landscape and
// driven by a controller: a top bar with Home, Library and Downloads (LB and
// RB), the Downloads badge, the controller's battery and the gear for
// Settings (≡); the page; and a footer naming what each button does, each
// entry also a tap. Presses come from PadRouter; directions and A go to the
// focus ring (PadFocus), the rest to the footer's entries. Touch works
// everywhere. A title's landscape screen replaces all of it (TitleLaunch).
//
// Settings (SettingsView.swift) replaces the whole frame: its list and a
// section, B back to the list and out. Downloads (DownloadsView.swift) names
// its own Y and X for the ringed job, and Download mode covers the whole
// frame, woken by any press. The game page (GameDetailView.swift) names its
// own buttons: A on the ringed control, X Game options, B back; in the
// options panel Y puts the ringed setting back to its default. The first-run
// checklist (SetupView.swift) replaces the pages on a first run or from
// Settings › Setup check. Sign in to Steam (SignInView.swift) covers
// whichever of them opened it.

import HostIOKit
import PlayportKit
import SwiftUI
import UniformTypeIdentifiers

struct AppShell: View {
    typealias Page = AppNavigation.Page

    @StateObject private var model = SteamAccountModel()
    @ObservedObject private var library = LibraryModel.shared
    @ObservedObject private var nav = AppNavigation.shared
    @ObservedObject private var focus = PadFocus.shared
    @ObservedObject private var router = PadRouter.shared
    @ObservedObject private var setup = JitSetup.shared
    @ObservedObject private var grid = LibraryGrid.shared
    @ObservedObject private var modal = PadModal.shared
    @ObservedObject private var gamePage = GamePageState.shared
    @ObservedObject private var setupState = SetupState.shared
    @ObservedObject private var opening = AppOpening.shared
    @Environment(\.launchingFromPage) private var launchingFromPage
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingMenu = false
    @State private var menuSelection = 0
    private static let menuPages = ["home", "library", "downloads", "settings"]
    @State private var importing = false
    /// What the one Files picker is open for: a pairing file, or a game (UI/Import.swift).
    @State private var importingGame = false
    @ObservedObject private var gog = GOGAccount.shared
    @ObservedObject private var epic = EpicAccount.shared

    var body: some View {
        VStack(spacing: 0) {
            GlassEffectContainer(spacing: 12) {
                TopBar(openMenu: openMenu).openingChrome()
                    .padding(.horizontal, 12)
            }
            .frame(height: 52)
            content.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 16)
            // Reserve the ordinary footer's height without mounting a second footer
            // when a game panel moves the same controls to the leading edge.
            Color.clear.frame(height: router.controller == nil || panelUp ? 0 : 44 + Self.footerBottom)
        }
        // The footer sits low, in the home indicator's inset, on every page.
        .ignoresSafeArea(.container, edges: .bottom)
        // Under a game page's panel the footer sits at the left, beside it (GameOptions.dc.html).
        .overlay(alignment: .bottomLeading) {
            if router.controller != nil {
                footer.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // A game's page: its hero art fills the screen behind it, dimmed as the launch screen
        // shows it (UI/LaunchViews.swift GameHeroArt). Clear once Play is
        // pressed: the launch screen's identical art under the diving page shows through.
        .backgroundPreferenceValue(PageArtKey.self) { art in
            if launchingFromPage {
                Color.clear
            } else if let art {
                ZStack { PP.background; GameHeroArt { art.view } }.ignoresSafeArea()
            } else {
                ambientBackground
            }
        }
        .overlay {
            GlassSidebar(isPresented: showingMenu, title: "PlayPort", subtitle: "遊戲啟動器",
                         dismiss: { showingMenu = false }) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array(Self.menuPages.enumerated()), id: \.element) { index, key in
                            GlassSidebarRow(title: menuTitle(key), icon: menuIcon(key),
                                            detail: key == "downloads" && !model.installs.jobs.isEmpty ? "\(model.installs.jobs.count)" : nil,
                                            selected: menuSelection == index) { chooseMenu(index) }
                                .accessibilityIdentifier(key == "settings" ? "navigation-settings" : "page-\(key)")
                        }
                    }
                }
            }
        }
        // The controller keyboard or a picker, over everything with its own footer.
        .overlay { PadModalHost().animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.25), value: modal.isUp) }
        // Download mode: black, over everything, until a button or a tap (DownloadsView.swift).
        .overlay { DownloadModeView(installs: model.installs) }
        // The opening animation, over everything until Home's cards have landed (UI/AppOpening.swift).
        .overlay { if opening.covering { OpeningView() } }
        // Dev builds: Settings › Developer › Black screen, over everything (Dev/BlackScreen.swift).
        .overlay {
            #if !PLAYPORT_RELEASE
            BlackScreenView()
            #endif
        }
        .padFocusRoot()
        .onReceive(PadRouter.shared.presses) { press($0) }
        // Choosing a pairing file (the checklist's step on iOS 26, Setup check's import), or a
        // game to import (Library › Add a game): touch only, as Files is. One picker for both:
        // SwiftUI presents only one fileImporter per hierarchy reliably.
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: importingGame ? GameImports.contentTypes : [.propertyList, .xml, .data]) { result in
            if importingGame {
                guard case let .success(url) = result else { return }
                Task {
                    if let refusal = await GameImports.shared.picked(url) {
                        PadModal.shared.picker(title: "Can't import \(url.lastPathComponent)", note: refusal,
                                               options: [PadOption(id: "ok", label: "OK")], selected: "ok") { _ in }
                    }
                }
            } else {
                BuiltInJitStatus.shared.importPairingFile(result)
            }
        }
        .onReceive(SettingsImport.requests) {
            importingGame = false
            importing = true
        }
        // GOG's and Epic's sign-in pages (touch: a web page, as iOS draws it; decision 0058).
        .sheet(isPresented: $gog.signingIn) { GOGSignInSheet() }
        .sheet(isPresented: $epic.signingIn) { EpicSignInSheet() }
        .onReceive(GameImports.requests) {
            importingGame = true
            importing = true
        }
        .environmentObject(model)
        .preferredColorScheme(.dark)
        .tint(PP.accent)
        .onAppear {
            PadRouter.shared.start()
            DownloadDimmer.shared.start(installs: model.installs)
            if scenePhase == .active { model.sceneBecameActive() }
            library.refresh()
            // Until each store has listed its games (today Steam's restore and list) and
            // Home's art is loaded, the opening animation covers the shell.
            opening.run { [model, library] in
                while !model.listedOnce || !library.scannedOnce { try? await Task.sleep(for: .milliseconds(50)) }
                await HomeView.loadArt(titles: library.catalog.titles, model: model)
            }
            // Built-in JIT's readiness check, once per launch, so Play rarely waits for the DDI mount.
            BuiltInJitStatus.shared.checkOnce()
            // A first run: the checklist (UI/SetupView.swift).
            SetupState.shared.showAtStartIfFirstRun()
            #if !PLAYPORT_RELEASE
            BlackScreen.restoreAtStart()
            UIDriver.startIfRequested()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.sceneBecameActive()
                library.refresh()
            } else {
                model.sceneLeftActive()
                DownloadDimmer.shared.sceneLeftActive()
                #if !PLAYPORT_RELEASE
                BlackScreen.shared.wake()
                #endif
            }
        }
    }

    private var content: some View {
        ZStack {
            // Retain each root's scroll and navigation state without a system tab bar.
            HomeView(installs: model.installs).modifier(RootPageVisibility(active: showsMainPages && nav.page == .home))
            LibraryView(installs: model.installs).modifier(RootPageVisibility(active: showsMainPages && nav.page == .library))
            DownloadsPage(installs: model.installs).modifier(RootPageVisibility(active: showsMainPages && nav.page == .downloads))

            if nav.signIn {
                SignInView().transition(.opacity)
            } else if nav.settings {
                SettingsView().transition(.opacity)
            } else if nav.setup {
                SetupView().transition(.opacity)
            }
        }
        .animation(shellAnimation, value: surface)
        .animation(shellAnimation, value: nav.page)
        .animation(shellAnimation, value: router.controller != nil)
    }

    private var footer: some View {
        GlassEffectContainer(spacing: 10) {
            PadFooter(hints: hints, leading: panelUp)
        }
        .overlay(alignment: .leading) {
            if onSetup, !modal.isUp {
                Text(SetupView.footerNote).font(.system(size: 12))
                    .foregroundStyle(PP.muted).padding(.leading, 44)
            }
            if nav.signIn, !modal.isUp {
                Text(SignInView.footerNote).font(.system(size: 12))
                    .foregroundStyle(PP.muted).padding(.leading, 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.trailing, panelUp ? 410 : 0)
        .padding(.bottom, Self.footerBottom)
        .opacity(modal.isUp ? 0 : 1)
        .allowsHitTesting(!modal.isUp)
        .accessibilityHidden(modal.isUp)
        .openingChrome()
        .animation(shellAnimation, value: panelUp)
    }

    private var ambientBackground: some View {
        ZStack {
            PP.background
            if let title = HomeView.continueTitle(library.catalog.titles) {
                GameArt(appID: title.appID, name: title.name, kind: .hero, titleID: title.id)
                    .opacity(0.14)
            }
            LinearGradient(colors: [PP.background.opacity(0.55), PP.background.opacity(0.95)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .ignoresSafeArea().allowsHitTesting(false)
    }

    private var showsMainPages: Bool { !nav.settings && !nav.setup && !nav.signIn }
    private var surface: String { nav.signIn ? "signin" : nav.settings ? "settings" : nav.setup ? "setup" : "main" }
    private var shellAnimation: Animation { reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.25) }

    /// The footer's distance from the screen's bottom edge, inside the home indicator's inset.
    static let footerBottom: CGFloat = 9

    /// Game options or the achievements over a game page: the panel runs to the bottom.
    private var panelUp: Bool { nav.onGamePage && !nav.gamePanels.isEmpty }

    /// The first-run checklist is the screen (not Settings over it).
    private var onSetup: Bool { nav.setup && !nav.settings && !nav.signIn }

    // MARK: buttons

    /// The footer: what each button does here.
    private var hints: [PadHint] {
        if showingMenu {
            return [PadHint(button: .a, label: "Open") { chooseMenu(menuSelection) },
                    PadHint(button: .b, label: "Close") { showingMenu = false }]
        }
        if nav.signIn { return SignInState.shared.hints(model) }
        if nav.onGamePage { return gamePageHints }
        if onSetup { return SetupView.hints() }
        var h: [PadHint] = []
        if let a = focus.hint, !a.isEmpty {
            h.append(PadHint(button: .a, label: a) { focus.activate() })
        }
        if nav.settings {
            // Settings.dc.html: A on the ringed row, B back to the list, then out.
            return h + [PadHint(button: .b, label: SettingsRing.backLabel) { _ = SettingsRing.press(.b) }]
        }
        if nav.page == .downloads {
            h += DownloadsPage.hints(model.installs, focused: focus.focused)
            // Main sections switch with LB/RB; B never leaves this page.
            return h + [PadHint(button: .menu, label: "選單", action: openMenu)]
        }
        if !nav.settings, nav.page == .library {
            let grid = LibraryGrid.shared
            h.append(PadHint(button: .view, label: "Filter & sort") { grid.openFilterSort() })
            h.append(PadHint(button: .y, label: "Search") { grid.openSearch() })
            // Add a game (UI/Import.swift): on every filter, not only at the grid's end.
            h.append(PadHint(button: .x, label: "Add a game") { GameImports.requests.send() })
            if !grid.search.isEmpty {
                h.append(PadHint(button: .b, label: "Clear search") { grid.clearSearch() })
                return h + [PadHint(button: .menu, label: "選單", action: openMenu)]
            }
        }
        if nav.canGoBack {
            h.append(PadHint(button: .b, label: "Back") { _ = nav.back() })
        }
        if !nav.settings {
            h.append(PadHint(button: .menu, label: "選單", action: openMenu))
        }
        return h
    }

    /// The game page's footer (Game.dc.html, GameOptions.dc.html): A on the ringed control, X
    /// its Game options (or the version, for a game not installed), B its origin; in the
    /// options panel Y puts the ringed setting back to its default and B closes it.
    private var gamePageHints: [PadHint] {
        var h: [PadHint] = []
        if nav.gamePanels.last != .achievements, let a = focus.hint, !a.isEmpty {
            h.append(PadHint(button: .a, label: a) { focus.activate() })
        }
        switch nav.gamePanels.last {
        case .options?:
            if focus.canReset { h.append(PadHint(button: .y, label: "Back to default") { focus.resetFocused() }) }
            h.append(PadHint(button: .b, label: "Close") { _ = nav.back() })
        case .achievements?:
            h.append(PadHint(button: .b, label: nav.gamePanels.count > 1 ? "Game options" : "Close") { _ = nav.back() })
        case nil:
            if let x = gamePage.x { h.append(PadHint(button: .x, label: x.label, action: x.action)) }
            h.append(PadHint(button: .b, label: nav.gameBackLabel) { _ = nav.back() })
        }
        return h
    }

    private func openMenu() {
        menuSelection = Self.menuPages.firstIndex(of: nav.settings ? "settings" : nav.page.rawValue) ?? 0
        showingMenu = true
    }

    private func chooseMenu(_ index: Int) {
        guard Self.menuPages.indices.contains(index) else { return }
        _ = nav.open(Self.menuPages[index])
        showingMenu = false
    }

    private func menuTitle(_ key: String) -> String {
        switch key { case "home": "Home"; case "library": "Library"; case "downloads": "Downloads"; default: "Settings" }
    }

    private func menuIcon(_ key: String) -> String {
        switch key { case "home": "house"; case "library": "square.grid.2x2"; case "downloads": "arrow.down.circle"; default: "gearshape" }
    }

    private func press(_ b: NavButton) {
        // The opening animation covers the shell: nothing to press yet.
        if opening.covering { return }
        #if !PLAYPORT_RELEASE
        // The black screen: any button wakes it, and does nothing else.
        if BlackScreen.shared.shown { return BlackScreen.shared.wake() }
        #endif
        // Download mode: any button wakes it, and does nothing else.
        let dimmer = DownloadDimmer.shared
        if dimmer.dimmed { return dimmer.wake() }
        dimmer.input()
        // A sheet over the shell (JIT setup) has the screen; alerts take touch only.
        guard !setup.presented else { return }
        // The system share sheet (Report a problem, a dev build's logs): B closes it.
        if ProblemReport.sheetUp { return ProblemReport.sheetPress(b) }
        // The controller keyboard or a picker takes every press while it is up.
        if modal.isUp { return modal.press(b) }
        if showingMenu {
            switch b {
            case .up: menuSelection = (menuSelection + Self.menuPages.count - 1) % Self.menuPages.count
            case .down: menuSelection = (menuSelection + 1) % Self.menuPages.count
            case .a: chooseMenu(menuSelection)
            case .b, .menu: showingMenu = false
            default: break
            }
            return
        }
        if b == .menu { openMenu(); return }
        // Sign in to Steam covers everything under it (UI/SignInView.swift).
        if nav.signIn { return SignInState.shared.press(b, model) }
        // Settings keeps the ring on its list or in the shown section (SettingsView.swift).
        if nav.settings, SettingsRing.press(b) { return }
        // The checklist: its steps with left and right or LB and RB (UI/SetupView.swift).
        if onSetup, SetupRing.press(b) { return }
        switch b {
        case .up: focus.move(.up)
        case .down: focus.move(.down)
        case .left: focus.move(.left)
        case .right: focus.move(.right)
        case .a: focus.activate()
        case .lb, .rb:
            guard !nav.settings, !nav.onGamePage else { return }
            nav.step(b == .lb ? -1 : 1)
        default:
            hints.first { $0.button == b }?.action()
        }
    }
}

/// Hidden roots retain state but contribute no hit targets or focus preferences.
private struct RootPageVisibility: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content.opacity(active ? 1 : 0)
            .offset(y: active ? 0 : 6)
            .allowsHitTesting(active).accessibilityHidden(!active)
            .transformPreference(PadItemsKey.self) { if !active { $0 = [:] } }
            .transformPreference(PageArtKey.self) { if !active { $0 = nil } }
    }
}

/// One navigation entry point; the drawer shares its surface with the game.
private struct TopBar: View {
    let openMenu: () -> Void
    @ObservedObject private var nav = AppNavigation.shared
    @ObservedObject private var router = PadRouter.shared

    private var secondary: Bool { nav.settings || nav.setup || nav.signIn || nav.onGamePage }
    private var title: String { nav.signIn ? "Steam" : nav.settings ? "Settings" : nav.setup ? "Setup" : nav.page.title }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openMenu) {
                Label("選單", systemImage: "sidebar.left").font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14).frame(minHeight: 44)
            }
            .buttonStyle(.plain).ppGlass(cornerRadius: 22)
            .accessibilityLabel("選單").accessibilityIdentifier("navigation-menu")
            if secondary {
                Button { _ = nav.back() } label: {
                    Label("Back", systemImage: "chevron.left").font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .buttonStyle(.plain).ppGlass(cornerRadius: 22)
                .disabled(!nav.canGoBack).accessibilityIdentifier("navigation-back")
            }
            if !nav.onGamePage { Text(LocalizedStringKey(title)).font(.system(size: 18, weight: .bold)) }
            Spacer(minLength: 8)
            if let controller = router.controller {
                Image(systemName: "gamecontroller.fill").font(.system(size: 15)).foregroundStyle(PP.muted)
                    .accessibilityLabel(controller.name)
            }
        }
        .foregroundStyle(PP.text)
    }
}
