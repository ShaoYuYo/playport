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
        guard isolated(url) else { return value }
        return value.replacingOccurrences(of: #"com\.apple\.dt\.Xcode(?:/[A-Za-z0-9._-]+)?"#,
            with: "com.apple.akd/1.0", options: .regularExpression)
    }
}
