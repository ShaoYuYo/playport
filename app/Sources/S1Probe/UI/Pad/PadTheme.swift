// SPDX-License-Identifier: GPL-3.0-or-later
// The gamepad UI's look (docs/design/2026-09-28-gamepad-ui/): one dark
// palette, the amber focus ring, and the button glyphs the footer and the top
// bar show.

import HostIOKit
import SwiftUI
import UIKit

enum PP {
    static let background = Color(hex: 0x10151D)
    static let surface = Color(hex: 0x1B2838)
    static let raised = Color(hex: 0x25364A)
    static let line = Color(hex: 0x35465A)
    static let text = Color(hex: 0xEEF1F5)
    static let soft = Color(hex: 0xC9D1DC)
    static let muted = Color(hex: 0x9AA5B4)
    static let accent = Color(hex: 0x66C0F4)
    static let onAccent = Color(hex: 0x071B2A)
    static let progress = Color(hex: 0x3DA9F5)
    static let ok = Color(hex: 0x6FCF7F)
    /// Art tiles without store art, in the design's colours, picked by name.
    static let tiles: [Color] = [0x24324A, 0x5B3A8C, 0x3E6A3A, 0x6E2B2B, 0x2F5A66, 0x6A5326].map { Color(hex: $0) }

    static func tile(for name: String) -> Color {
        tiles[Int(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }) % tiles.count]
    }

    /// Native system headings keep controls and content on the same type scale.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
}

/// One drawer surface for library navigation and the paused game.
struct GlassSidebar<Content: View>: View {
    let isPresented: Bool
    let title: String
    let subtitle: String
    let dismiss: () -> Void
    @ViewBuilder let content: () -> Content
    @ObservedObject private var safe = WindowInsets.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if isPresented {
                    Color.black.opacity(0.38).contentShape(Rectangle())
                        .onTapGesture(perform: dismiss).transition(.opacity)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(LocalizedStringKey(subtitle)).font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(PP.muted)
                                Text(title).font(PP.display(23)).lineLimit(2).minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 0)
                            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 36, height: 36) }
                                .buttonStyle(.plain).background(.white.opacity(0.08), in: Circle())
                                .accessibilityLabel("Close")
                        }
                        content()
                    }
                    .padding(18)
                    .padding(.leading, max(0, safe.insets.leading - 12))
                    .padding(.top, max(0, safe.insets.top - 12))
                    .padding(.bottom, max(0, safe.insets.bottom - 12))
                    .frame(width: min(360 + max(0, safe.insets.leading - 12), max(0, geometry.size.width - 24)))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ppGlass(cornerRadius: 26, interactive: false)
                    .padding(12)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.32, dampingFraction: 0.9), value: isPresented)
        }
        .ignoresSafeArea()
        .foregroundStyle(PP.text)
        .allowsHitTesting(isPresented).accessibilityHidden(!isPresented)
    }
}

struct GlassSidebarRow: View {
    let title: String
    let icon: String
    var detail: String? = nil
    var selected = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassSidebarRowLabel(title: title, icon: icon, detail: detail, selected: selected, destructive: destructive)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Presentation shared by ordinary buttons and the controller focus system.
struct GlassSidebarRowLabel: View {
    let title: String
    let icon: String
    var detail: String? = nil
    var selected = false
    var destructive = false

    var body: some View {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium)).frame(width: 23)
                Text(LocalizedStringKey(title)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if let detail { Text(LocalizedStringKey(detail)).font(.system(size: 11)).foregroundStyle(PP.muted).lineLimit(1) }
            }
            .foregroundStyle(destructive ? Color(hex: 0xFF9A8A) : PP.text)
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(selected ? PP.accent.opacity(0.2) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(selected ? 0.24 : 0.07), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 13))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// A controller button as the footer and the top bar draw it: a light pill with its name.
struct PadGlyph: View {
    let button: NavButton
    var inverted = false

    var body: some View {
        Text(Self.name(button))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(inverted ? PP.accent : PP.background)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(inverted ? PP.onAccent : PP.text, in: Capsule())
    }

    static func name(_ b: NavButton) -> String {
        switch b {
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .lb: "LB"
        case .rb: "RB"
        case .menu: "≡"
        case .view: "⧉"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        }
    }
}

/// One footer entry: what `button` does on this screen. Tapping it does the same.
struct PadHint: Identifiable {
    let button: NavButton
    let label: String
    let action: () -> Void
    var id: NavButton { button }
}

/// The footer every screen has: its buttons, right-aligned, each tappable.
/// `leading`: at the left with no rule above it, beside a panel at the right
/// (GameOptions.dc.html), as a picker's own footer is.
struct PadFooter: View {
    let hints: [PadHint]
    var leading = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            if !leading { Spacer(minLength: 0) }
            ForEach(hints) { h in
                Button(action: h.action) {
                    HStack(spacing: 6) {
                        PadGlyph(button: h.button)
                        Text(LocalizedStringKey(h.label)).font(.system(size: 13)).foregroundStyle(PP.soft)
                            .contentTransition(.opacity)
                    }
                    .padding(.horizontal, 4).frame(minHeight: 28)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .transition(.opacity)
                .accessibilityIdentifier("hint-\(h.button.rawValue)")
            }
            if leading { Spacer(minLength: 0) }
        }
        .frame(height: 44)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: hints.map { $0.button.rawValue + ":" + $0.label })
    }
}

/// The window's safe area, for views over the game surface: the surface
/// ignores the safe area, and so does what is laid over it, so SwiftUI
/// reports no insets there. In landscape the Dynamic Island takes the
/// leading or trailing edge, whichever way the phone is turned; these are
/// read from the window, and again whenever the phone turns.
@MainActor
final class WindowInsets: ObservableObject {
    static let shared = WindowInsets()
    @Published private(set) var insets = EdgeInsets()
    private var observer: NSObjectProtocol?

    private init() {
        read()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        observer = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                                          object: nil, queue: .main) { _ in
            // The window's insets follow the rotation a moment later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { WindowInsets.shared.read() } }
        }
    }

    /// Reads the key window's insets now; the line for the log.
    @discardableResult
    func read() -> String {
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
        let i = window?.safeAreaInsets ?? .zero
        let e = EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
        if e != insets { insets = e }
        return "safe area top=\(Int(i.top)) left=\(Int(i.left)) bottom=\(Int(i.bottom)) right=\(Int(i.right))"
            + (window == nil ? " (no key window)" : "")
    }

    /// A horizontal margin of at least `margin` inside the safe area on each side.
    var leading: CGFloat { insets.leading }
    var trailing: CGFloat { insets.trailing }
    func side(_ margin: CGFloat, _ inset: CGFloat) -> CGFloat { max(margin, inset + 8) }
}
