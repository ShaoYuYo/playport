// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Steam's language IDs differ from iOS language identifiers.
public enum GameLanguage: String, CaseIterable, Sendable {
    case english, tchinese, schinese, japanese
    public static let preferenceKey = "playport.game-language"

    public var title: String {
        switch self {
        case .english: "English"
        case .tchinese: "繁體中文"
        case .schinese: "简体中文"
        case .japanese: "日本語"
        }
    }

    public static func suggested(_ preferred: [String] = Locale.preferredLanguages) -> Self {
        let first = (preferred.first ?? "en").lowercased().replacingOccurrences(of: "_", with: "-")
        if first.hasPrefix("zh") {
            if first.contains("hant") { return .tchinese }
            if first.contains("hans") { return .schinese }
            return ["-tw", "-hk", "-mo"].contains(where: first.contains) ? .tchinese : .schinese
        }
        return first.hasPrefix("ja") ? .japanese : .english
    }

    public static var current: Self {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? suggested()
    }
}
