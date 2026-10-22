// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// GrandSlam's verified SRP response can carry a challenge in several envelopes.
/// HTTP challenge metadata is never treated as authentication success.
enum AppleTwoFactorPolicy {
    enum Challenge: Equatable { case trustedDevice(alreadySent: Bool), sms, none, unsupported }
    static func challenge(in reply: [String: Any]) -> Challenge {
        let status = reply["Status"] as? [String: Any] ?? [:]
        let mode = status["au"] as? String ?? reply["au"] as? String
        switch mode {
        case "trustedDeviceSecondaryAuth", "trustedDevice": return .trustedDevice(alreadySent: false)
        case "pushedCode": return .trustedDevice(alreadySent: true)
        case "secondaryAuth", "sms", "phone": return .sms
        case nil, "":
            return (status["hsc"] as? NSNumber)?.intValue == 409 ? .trustedDevice(alreadySent: true) : .none
        default: return .unsupported
        }
    }
    static func rejection(in data: Data) -> Int? {
        guard !data.isEmpty,
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let reply = root["Response"] as? [String: Any] ?? root
        let status = reply["Status"] as? [String: Any] ?? [:]
        let code = (reply["ec"] as? NSNumber)?.intValue ?? (status["ec"] as? NSNumber)?.intValue ?? 0
        return code == 0 ? nil : code
    }
}
