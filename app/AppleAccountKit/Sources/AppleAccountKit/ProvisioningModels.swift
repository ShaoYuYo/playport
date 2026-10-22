// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum AppleProvisioningError: Error, LocalizedError {
    case invalidReply, transport, http(Int), rejected(Int), cancelled, unsupportedAuthentication
    case missingApp, ambiguousApp, capabilityNotConfirmed, invalidCapabilitySnapshot, invalidVerificationCode
    public var errorDescription: String? {
        switch self {
        case .invalidReply: return "Apple 回覆格式無法辨識，無法確認設定結果。請重新整理。"
        case .http(let status): return "服務回覆 HTTP \(status)，無法確認設定結果。請稍後重試；如持續發生，請提供這個狀態碼。"
        case .transport: return "無法安全連接服務，請檢查網路後重試。"
        case .rejected(-80045): return "Apple 暫時拒絕此登入用戶端（-80045），未完成帳號驗證。這個代碼不能用來判定密碼錯誤；請稍後重試或使用原側載工具處理權限。"
        case .rejected(let code): return "Apple 拒絕要求（\(code)）。請確認帳號、驗證碼與開發者協議。"
        case .invalidVerificationCode: return "請輸入 Apple 的六位數字驗證碼，驗證尚未完成。"
        case .cancelled: return "已取消登入。"
        case .unsupportedAuthentication: return "此帳號的驗證方式目前無法完成，未更動權限。"
        case .missingApp: return "所選團隊找不到目前 Playport 的 App ID；請使用側載時的 Apple 帳號與團隊。"
        case .ambiguousApp: return "找到多個符合的 App ID，未自動修改。"
        case .capabilityNotConfirmed: return "Apple 尚未確認權限已啟用；未宣稱成功，請重新整理。"
        case .invalidCapabilitySnapshot: return "無法完整讀取現有權限，為保留原設定，本次未修改。"
        }
    }
}

public struct DeveloperTeam: Identifiable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}
public struct DeveloperApp: Identifiable, Sendable {
    public let id: String
    public let bundleID: String
    public let name: String
    public init(id: String, bundleID: String, name: String) { self.id = id; self.bundleID = bundleID; self.name = name }
}

public enum MemoryCapability {
    public static let identifier = "INCREASED_MEMORY_LIMIT"
    /// Match only the installed identifier, never an unrelated app or a suffix.
    public static func select(_ apps: [DeveloperApp], installedBundleID: String) throws -> DeveloperApp {
        let matches = apps.filter { $0.bundleID == installedBundleID }
        guard !matches.isEmpty else { throw AppleProvisioningError.missingApp }
        guard matches.count == 1 else { throw AppleProvisioningError.ambiguousApp }
        return matches[0]
    }

    /// A complete JSON:API relationship snapshot is required before a PATCH.
    /// Every existing capability and its opaque settings are retained verbatim.
    public static func updatedCapabilities(_ snapshot: [String: Any]) throws -> [[String: Any]] {
        guard let data = snapshot["data"] as? [String: Any],
              let relationships = data["relationships"] as? [String: Any],
              let relation = relationships["bundleIdCapabilities"] as? [String: Any],
              let links = relation["data"] as? [[String: Any]] else { throw AppleProvisioningError.invalidCapabilitySnapshot }
        if let pagination = relation["links"] as? [String: Any], let next = pagination["next"], !(next is NSNull) {
            throw AppleProvisioningError.invalidCapabilitySnapshot
        }
        guard Set(links.compactMap { $0["id"] as? String }).count == links.count else { throw AppleProvisioningError.invalidCapabilitySnapshot }
        let included = snapshot["included"] as? [[String: Any]] ?? []
        var result: [[String: Any]] = []
        var found = false
        for link in links {
            guard let id = link["id"] as? String,
                  let full = included.first(where: { $0["id"] as? String == id && $0["type"] as? String == "bundleIdCapabilities" }),
                  let attrs = full["attributes"] as? [String: Any],
                  let rels = full["relationships"] as? [String: Any],
                  let capability = rels["capability"] as? [String: Any],
                  let capData = capability["data"] as? [String: Any], let capID = capData["id"] as? String,
                  attrs["enabled"] is Bool, attrs["settings"] != nil else { throw AppleProvisioningError.invalidCapabilitySnapshot }
            var item = full
            if capID == identifier {
                var a = attrs; a["enabled"] = true; item["attributes"] = a; found = true
            }
            // Do not include server-generated top-level navigation links.
            item.removeValue(forKey: "links")
            result.append(item)
        }
        if !found {
            result.append(["type": "bundleIdCapabilities", "attributes": ["enabled": true, "settings": []],
                "relationships": ["capability": ["data": ["type": "capabilities", "id": identifier]]]])
        }
        return result
    }

    /// Reuse editable values read from this App ID; never invent a seed/prefix
    /// or turn an unknown managed-capability flag into false.
    public static func preservedAttributes(_ snapshot: [String: Any], installedBundleID: String) throws -> [String: Any] {
        guard let data = snapshot["data"] as? [String: Any], let attrs = data["attributes"] as? [String: Any],
              attrs["identifier"] as? String == installedBundleID else { throw AppleProvisioningError.invalidCapabilitySnapshot }
        let allowed: Set<String> = ["identifier", "name", "teamId", "seedId", "bundleType", "hasExclusiveManagedCapabilities"]
        return attrs.filter { allowed.contains($0.key) }
    }

    public static func isEnabled(_ snapshot: [String: Any]) -> Bool {
        guard let root = snapshot["data"] as? [String: Any], let rels = root["relationships"] as? [String: Any],
              let relation = rels["bundleIdCapabilities"] as? [String: Any], let links = relation["data"] as? [[String: Any]] else { return false }
        let ids = Set(links.compactMap { $0["id"] as? String })
        let included = (snapshot["included"] as? [[String: Any]] ?? []).filter { ids.contains($0["id"] as? String ?? "") && $0["type"] as? String == "bundleIdCapabilities" }
        return included.contains { item in
            guard let rel = item["relationships"] as? [String: Any], let cap = rel["capability"] as? [String: Any],
                  let data = cap["data"] as? [String: Any], data["id"] as? String == identifier,
                  let attrs = item["attributes"] as? [String: Any] else { return false }
            return attrs["enabled"] as? Bool == true
        }
    }
}
