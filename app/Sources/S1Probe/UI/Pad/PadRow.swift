// SPDX-License-Identifier: GPL-3.0-or-later
// The list row of Settings, Game options and Downloads
// (Settings.dc.html, SettingsGraphics.dc.html, GameOptions.dc.html): a title,
// an optional grey line under it, and at the right a value or detail and an
// accessory (a chevron, a switch). A dot before the value marks a setting
// changed for this game. The row is a focus item: A and a tap run it.
//
// Two looks: `.card`, a filled row with room for the grey line (Settings),
// and `.plain`, a 38 pt line in a panel (Game options), which fills light
// when the focus is on it (GameOptions.dc.html) instead of taking the ring.
// PadSectionHeader is the small capitals above a group of plain rows.

import SwiftUI

enum PadRowStyle {
    case card
    case plain
}

enum PadRowAccessory: Equatable {
    case none
    /// ›, a row that opens something (a picker, a page).
    case chevron
    /// A switch, on or off.
    case toggle(Bool)
}

struct PadRow: View {
    let id: String
    let title: String
    var subtitle: String?
    /// The value or detail at the right ("Default · 720p", "Frees 9.2 GB").
    var value: String?
    var accessory = PadRowAccessory.none
    /// Changed for this game: the amber dot before the value.
    var changed = false
    /// A row that removes something (Uninstall): its title in red.
    var destructive = false
    var style = PadRowStyle.card
    /// What A does on it, for the footer.
    var hint = "Choose"
    /// Y on the row: its value back to the default (a game's option set for it).
    var reset: (() -> Void)?
    let action: () -> Void
    @ObservedObject private var focus = PadFocus.shared

    var body: some View {
        let selected = style == .plain && focus.focused == id
        PadRowBody(title: title, subtitle: subtitle, style: style, destructive: destructive, selected: selected) {
            HStack(spacing: 6) {
                if changed { Circle().fill(PP.accent).frame(width: 7, height: 7) }
                if let value {
                    Text(LocalizedStringKey(value)).lineLimit(2).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }
                switch accessory {
                case .none: EmptyView()
                case .chevron: Text("›")
                case .toggle(let on): PadSwitch(on: on)
                }
            }
            .font(.system(size: 13)).foregroundStyle(selected ? PP.raised : PP.muted)
        }
        .padItem(id, hint: hint, cornerRadius: 10, reset: reset, ring: style != .plain, action: action)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: Text {
        if case .toggle(let on) = accessory {
            return Text(LocalizedStringKey(on ? "On" : "Off"))
        }
        return Text(LocalizedStringKey(value ?? ""))
    }
}

/// A row's frame and title; `trailing` is its right side.
struct PadRowBody<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var style = PadRowStyle.card
    var destructive = false
    /// A plain row with the focus on it: filled light, its text dark.
    var selected = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(title)).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? (destructive ? Color(hex: 0xB0301E) : PP.background)
                                     : destructive ? PP.danger : PP.text)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle)).font(.system(size: 12)).foregroundStyle(selected ? PP.raised : PP.muted)
                }
            }
            .lineLimit(style == .card ? 3 : 2)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, style == .card ? 12 : 8)
        .frame(minHeight: style == .card ? 56 : 44)
        .frame(maxWidth: .infinity)
        .background(selected ? PP.text : style == .card ? PP.surface.opacity(0.94) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay { if style == .card { RoundedRectangle(cornerRadius: 12).strokeBorder(PP.line.opacity(0.45), lineWidth: 0.5) } }
    }
}

/// The small grey capitals over a group of rows ("GRAPHICS").
struct PadSectionHeader: View {
    let text: String

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 11, weight: .semibold)).tracking(1.1)
            .foregroundStyle(PP.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
    }
}

/// A native switch indicator; the surrounding focusable row handles touch and
/// controller activation. The system supplies appearance and accessible motion.
struct PadSwitch: View {
    let on: Bool

    var body: some View {
        Toggle(isOn: .constant(on)) { EmptyView() }
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(PP.accent)
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
