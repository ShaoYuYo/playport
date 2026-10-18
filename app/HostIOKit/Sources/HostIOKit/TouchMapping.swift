// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Event-driven menu visibility. The UI schedules at most the next deadline;
/// it does not poll. A tap opens the same fixed target even while hidden.
public struct EdgeMenuVisibility: Sendable {
    public static let preferenceKey = "controls.menuAutoHide"
    public static let delay = 2.5
    public private(set) var active = false
    public private(set) var shown = false
    public private(set) var deadline: Double?
    private var autoHide = false, editing = false, held = false, hovering = false
    public init() {}

    public mutating func configure(active: Bool, autoHide: Bool, editing: Bool, now: Double) {
        guard self.active != active || self.autoHide != autoHide || self.editing != editing else { return }
        self.active = active; self.autoHide = autoHide; self.editing = editing
        held = false
        if !active { hovering = false }
        shown = active
        schedule(now: now)
    }
    private mutating func schedule(now: Double) {
        deadline = active && shown && autoHide && !editing && !held && !hovering ? now + Self.delay : nil
    }
    public mutating func begin(now: Double) {
        guard active else { return }
        held = true; shown = true; deadline = nil
    }
    public mutating func end(inside: Bool, now: Double) -> Bool {
        guard active, held else { return false }
        let open = inside
        held = false; schedule(now: now)
        return open
    }
    public mutating func hover(_ inside: Bool, now: Double) {
        guard active else { hovering = false; return }
        hovering = inside
        if inside { shown = true }
        schedule(now: now)
    }
    public mutating func expire(now: Double) {
        guard let deadline, now >= deadline, active, autoHide, !editing, !held, !hovering else { return }
        shown = false; self.deadline = nil
    }
}

/// On-screen controls use the same HID-to-Windows path as a hardware keyboard.
public enum TouchAction: String, Codable, CaseIterable, Sendable {
    case enter, space, escape, control, shift, tab, backspace
    case up, down, left, right, pageUp, pageDown
    case mouseLeft, mouseRight
    case key0, key1, key2, key3, key4, key5, key6, key7, key8, key9
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    public var title: String {
        switch self {
        case .enter: "Enter"
        case .space: "Space"
        case .escape: "Esc"
        case .control: "Ctrl"
        case .shift: "Shift"
        case .tab: "Tab"
        case .backspace: "⌫"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .pageUp: "PgUp"
        case .pageDown: "PgDn"
        case .mouseLeft: "左鍵"
        case .mouseRight: "右鍵"
        default: rawValue.hasPrefix("key") ? String(rawValue.dropFirst(3)) : rawValue.uppercased()
        }
    }

    public var hidUsage: Int? {
        switch self {
        case .enter: 0x28
        case .space: 0x2c
        case .escape: 0x29
        case .control: 0xe0
        case .shift: 0xe1
        case .tab: 0x2b
        case .backspace: 0x2a
        case .up: 0x52
        case .down: 0x51
        case .left: 0x50
        case .right: 0x4f
        case .pageUp: 0x4b
        case .pageDown: 0x4e
        case .mouseLeft, .mouseRight: nil
        default:
            if rawValue.hasPrefix("key"), let n = Int(rawValue.dropFirst(3)) { n == 0 ? 0x27 : 0x1e + n - 1 }
            else if rawValue.count == 1, let value = rawValue.utf8.first { Int(value) - 97 + 4 }
            else if let number = Int(rawValue.dropFirst()) { 0x3a + number - 1 }
            else { nil }
        }
    }
}

public struct TouchBinding: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var action: TouchAction
    public var label: String
    /// Normalized coordinates within the safe control canvas.
    public var x: Double
    public var y: Double

    public init(id: UUID = UUID(), action: TouchAction, label: String? = nil, x: Double, y: Double) {
        self.id = id; self.action = action; self.label = label ?? action.title
        self.x = x; self.y = y
    }
}

public struct TouchLayout: Codable, Equatable, Sendable {
    public var enabled = true
    public var docked = false
    public var opacity = 0.72
    public var buttons: [TouchBinding] = []
    public init() {}

    private enum CodingKeys: String, CodingKey { case enabled, docked, opacity, buttons }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        docked = try values.decodeIfPresent(Bool.self, forKey: .docked) ?? true
        opacity = try values.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.72
        buttons = try values.decodeIfPresent([TouchBinding].self, forKey: .buttons) ?? buttons
    }

    /// Bound persistent/user-edited data before it reaches SwiftUI positions.
    public var normalized: TouchLayout {
        var value = self
        value.opacity = opacity.isFinite ? min(1, max(0.2, opacity)) : 0.72
        var seen = Set<UUID>()
        value.buttons = buttons.prefix(20).filter { seen.insert($0.id).inserted }.map { b in
            var result = b
            result.x = b.x.isFinite ? min(1, max(0, b.x)) : 0.5
            result.y = b.y.isFinite ? min(1, max(0, b.y)) : 0.5
            result.label = String(b.label.prefix(12))
            if result.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.label = b.action.title }
            return result
        }
        return value
    }
}

/// Several screen controls and a hardware key may hold the same guest input.
/// Only the first down and last up are forwarded, so one finger cannot release
/// another finger's Ctrl. Clear this alongside Lifecycle's release actions.
public struct InputOwners: Sendable {
    private var owners: [Int: Set<String>] = [:]
    public init() {}
    public mutating func update(code: Int, source: String, down: Bool) -> Bool {
        var set = owners[code] ?? []
        let wasDown = !set.isEmpty
        if down { set.insert(source) } else { set.remove(source) }
        owners[code] = set.isEmpty ? nil : set
        return wasDown != !set.isEmpty
    }
    public mutating func clear() { owners.removeAll() }
}
