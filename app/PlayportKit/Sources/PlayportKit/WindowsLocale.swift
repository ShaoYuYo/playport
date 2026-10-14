// SPDX-License-Identifier: GPL-3.0-or-later
/// Compatibility profiles for legacy Windows system (ANSI) locales.
///
/// This controls Wine's system code page, not PlayPort's interface language
/// or Steam's per-game language choice. Wine reads LANG/LC_ALL while its
/// ntdll is starting, before the guest executable gets its own environment.
public enum WindowsLocale {
    public static func startupOverride(steamAppID: UInt32?) -> String? {
        switch steamAppID {
        case 1144400:
            // Senren＊Banka uses legacy Japanese strings during startup.
            // Preserve the player's separately chosen Steam/UI language.
            return "ja_JP.UTF-8"
        default:
            return nil
        }
    }
}
