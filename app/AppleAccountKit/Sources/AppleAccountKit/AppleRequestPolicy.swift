// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// GrandSlam's current authentication edge must not share spent connections.
/// Apply its client descriptor policy only to the authentication origin; the
/// developer portal and the public anisette service retain their descriptors.
enum AppleRequestPolicy {
    static func isolated(_ url: URL?) -> Bool {
        url?.scheme == "https" && url?.host?.lowercased() == "gsa.apple.com"
    }
    static func clientInfo(_ value: String, url: URL) -> String {
        guard grandSlam(url) else { return value }
        // A token-only replacement retained the rejected Mac hardware/OS
        // descriptor. Scope the compatible complete identity to the SRP origin
        // and validate endpoint; provisioning, 2FA pages and portal stay native.
        return "<PC> <Windows;6.2(0,0);9200> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"
    }
    static func grandSlam(_ url: URL?) -> Bool {
        guard isolated(url), let path = url?.path else { return false }
        return path == "/grandslam/GsService2" || path == "/grandslam/GsService2/validate"
    }
    static func authenticationHeaders(_ url: URL) -> [String: String] {
        guard grandSlam(url) else { return [:] }
        return ["User-Agent": "akd/1.0 CFNetwork/808.1.4", "Accept": "text/x-xml-plist",
                "X-Apple-App-Info": "com.apple.gs.xcode.auth", "X-Xcode-Version": "7.0 (7A120f)"]
    }
    static func rejection(in data: Data) -> Int? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let reply = root["Response"] as? [String: Any], let status = reply["Status"] as? [String: Any],
              let code = status["ec"] as? NSNumber, code.intValue != 0 else { return nil }
        return code.intValue
    }
}
