// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CryptoSwift

private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == task.originalRequest?.url?.host &&
                          (request.url?.port ?? 443) == (task.originalRequest?.url?.port ?? 443) ? request : nil)
    }
}

/// Account/provisioning only. Never linked to the Windows translator and never
/// exposes passwords, tokens, anisette or Apple response bodies to app logs.
public actor AppleMemoryClient {
    private let http: URLSession
    private let anisetteServer = URL(string: "https://ani.sidestore.io")!
    private let service = URL(string: "https://developerservices2.apple.com/services/")!
    private var identity: [String: String]?
    private var anisette: [String: String] = [:]
    private var clientInfo = "", userAgent = "Xcode"
    private var accountID = "", token = ""
    public init(identityRecord: Data? = nil) {
        if let identityRecord, let record = try? JSONDecoder().decode([String: String].self, from: identityRecord),
           let identifier = record["identifier"], Data(base64Encoded: identifier)?.count == 16,
           record["adi_pb"] != nil { identity = record }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.urlCache = nil
        http = URLSession(configuration: configuration, delegate: SameOriginRedirects(), delegateQueue: nil)
    }
    deinit { http.invalidateAndCancel() }
    public func identityRecord() throws -> Data? { try identity.map { try JSONEncoder().encode($0) } }
    public func forgetSession() { token = ""; accountID = ""; anisette = [:] }

    private func checkedURL(_ raw: String) throws -> URL {
        guard let url = URL(string: raw), url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host, host == "apple.com" || host.hasSuffix(".apple.com") else { throw AppleProvisioningError.transport }
        return url
    }
    private func receive(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let transient: URLSession?
        if AppleRequestPolicy.isolated(request.url) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 90
            configuration.httpMaximumConnectionsPerHost = 1
            configuration.httpShouldUsePipelining = false
            configuration.urlCache = nil
            transient = URLSession(configuration: configuration, delegate: SameOriginRedirects(), delegateQueue: nil)
        } else { transient = nil }
        defer { transient?.invalidateAndCancel() }
        let (data, response) = try await (transient ?? http).data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AppleProvisioningError.transport }
        guard (200..<300).contains(response.statusCode) else { throw AppleProvisioningError.http(response.statusCode) }
        guard data.count <= 2 << 20 else { throw AppleProvisioningError.invalidReply }
        return data
    }
    private func dictionary(_ data: Data, json: Bool = false) throws -> [String: Any] {
        let value: Any = try json ? JSONSerialization.jsonObject(with: data)
            : PropertyListSerialization.propertyList(from: data, format: nil)
        guard let result = value as? [String: Any] else { throw AppleProvisioningError.invalidReply }
        return result
    }
    private func request(_ url: URL, method: String = "POST", body: [String: Any]? = nil,
                         headers: [String: String] = [:], json: Bool = false) throws -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue(json ? "application/vnd.api+json" : "text/x-xml-plist", forHTTPHeaderField: "Content-Type")
        request.setValue(json ? "application/json" : "*/*", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(AppleRequestPolicy.clientInfo(clientInfo, url: url), forHTTPHeaderField: "X-MMe-Client-Info")
        request.setValue("close", forHTTPHeaderField: "Connection")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body {
            request.httpBody = try json ? JSONSerialization.data(withJSONObject: body)
                : PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        }
        return request
    }
    private static func digest(_ data: Data) -> Data { Data(Array(data).sha256()) }
    private static func mac(_ key: Data, _ message: Data) -> Data {
        Data((try? CryptoSwift.HMAC(key: Array(key), variant: .sha2(.sha256)).authenticate(Array(message))) ?? [])
    }
    private func identityHeaders(_ identifier: String) throws -> [String: String] {
        guard let data = Data(base64Encoded: identifier), data.count == 16 else { throw AppleProvisioningError.invalidReply }
        let b = Array(data)
        let uuid = UUID(uuid: (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]))
        return ["X-Apple-I-MD-LU": Self.digest(data).map { String(format: "%02x", $0) }.joined(),
            "X-Mme-Device-Id": uuid.uuidString, "X-Apple-I-Client-Time": ISO8601DateFormatter().string(from: Date()),
            "X-Apple-Locale": Locale.current.identifier, "X-Apple-I-TimeZone": TimeZone.current.abbreviation() ?? "UTC"]
    }
    private func refreshAnisette() async throws {
        let infoData = try await receive(request(anisetteServer.appendingPathComponent("v3/client_info"), method: "GET"))
        let info = try dictionary(infoData, json: true)
        guard let description = info["client_info"] as? String, let agent = info["user_agent"] as? String else { throw AppleProvisioningError.invalidReply }
        clientInfo = description; userAgent = agent
        if identity == nil {
            var rng = SystemRandomNumberGenerator()
            let identifier = Data((0..<16).map { _ in UInt8.random(in: 0...255, using: &rng) }).base64EncodedString()
            let ih = try identityHeaders(identifier)
            let lookupData = try await receive(request(try checkedURL("https://gsa.apple.com/grandslam/GsService2/lookup"), method: "GET", headers: ih))
            let lookup = try dictionary(lookupData)
            guard let urls = lookup["urls"] as? [String: String], let begin = urls["midStartProvisioning"], let end = urls["midFinishProvisioning"] else { throw AppleProvisioningError.invalidReply }
            let beginURL = try checkedURL(begin), endURL = try checkedURL(end)
            var components = URLComponents(url: anisetteServer.appendingPathComponent("v3/provisioning_session"), resolvingAgainstBaseURL: false)!
            components.scheme = "wss"
            let socket = http.webSocketTask(with: components.url!); socket.maximumMessageSize = 1 << 20
            socket.resume(); defer { socket.cancel(with: .normalClosure, reason: nil) }
            var provisioned: String?
            for _ in 0..<8 {
                let message = try await socket.receive()
                let bytes: Data
                switch message { case .data(let d): bytes = d; case .string(let s): bytes = Data(s.utf8); @unknown default: throw AppleProvisioningError.invalidReply }
                let item = try dictionary(bytes, json: true)
                let output: [String: String]
                switch item["result"] as? String {
                case "GiveIdentifier": output = ["identifier": identifier]
                case "GiveStartProvisioningData":
                    let start = try await receive(request(beginURL, body: ["Header": [:], "Request": [:]], headers: ih))
                    guard let response = try dictionary(start)["Response"] as? [String: Any], let spim = response["spim"] as? String else { throw AppleProvisioningError.invalidReply }
                    output = ["spim": spim]
                case "GiveEndProvisioningData":
                    guard let cpim = item["cpim"] as? String else { throw AppleProvisioningError.invalidReply }
                    let finish = try await receive(request(endURL, body: ["Header": [:], "Request": ["cpim": cpim]], headers: ih))
                    guard let response = try dictionary(finish)["Response"] as? [String: Any], let ptm = response["ptm"] as? String, let tk = response["tk"] as? String else { throw AppleProvisioningError.invalidReply }
                    output = ["ptm": ptm, "tk": tk]
                case "ProvisioningSuccess": provisioned = item["adi_pb"] as? String; output = [:]
                default: throw AppleProvisioningError.invalidReply
                }
                if provisioned != nil { break }
                try await socket.send(.string(String(decoding: JSONSerialization.data(withJSONObject: output), as: UTF8.self)))
            }
            guard let provisioned else { throw AppleProvisioningError.invalidReply }
            identity = ["identifier": identifier, "adi_pb": provisioned]
        }
        guard let identity, let identifier = identity["identifier"] else { throw AppleProvisioningError.invalidReply }
        let freshData = try await receive(request(anisetteServer.appendingPathComponent("v3/get_headers"), body: identity, headers: ["Content-Type": "application/json"], json: true))
        let fresh = try dictionary(freshData, json: true)
        var headers = try identityHeaders(identifier)
        for key in ["X-Apple-I-MD", "X-Apple-I-MD-M", "X-Apple-I-MD-RINFO"] {
            guard let value = fresh[key] as? String, !value.isEmpty else { throw AppleProvisioningError.invalidReply }
            headers[key] = value
        }
        anisette = headers
    }
    private func authenticateRequest(_ parameters: [String: Any]) async throws -> [String: Any] {
        let data = try await receive(request(try checkedURL("https://gsa.apple.com/grandslam/GsService2"),
            body: ["Header": ["Version": "1.0.1"], "Request": parameters]))
        guard let response = try dictionary(data)["Response"] as? [String: Any], let status = response["Status"] as? [String: Any] else { throw AppleProvisioningError.invalidReply }
        let code = (status["ec"] as? NSNumber)?.intValue ?? 0
        guard code == 0 else { throw AppleProvisioningError.rejected(code) }
        return response
    }
    /// SRP server proof is verified before opening Apple's encrypted session.
    /// Credentials/proofs only go to gsa.apple.com, not the anisette service.
    public func signIn(email: String, password: String,
                       verification: @Sendable (_ sms: Bool) async throws -> String) async throws -> [DeveloperTeam] {
        accountID = ""; token = ""
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty, !password.isEmpty else { throw AppleProvisioningError.cancelled }
        for round in 0..<2 {
            try await refreshAnisette()
            var cpd: [String: Any] = anisette
            cpd["X-Apple-I-SRL-NO"] = "0"
            cpd.merge(["bootstrap": true, "icscrec": true, "pbe": false, "prkgen": true,
                "svct": "iCloud", "loc": Locale.current.identifier]) { _, new in new }
            let srp = AppleSRP()
            let start = try await authenticateRequest(["o": "init", "u": email, "A2k": srp.publicKey, "ps": ["s2k", "s2k_fo"], "cpd": cpd])
            guard let salt = start["s"] as? Data, let b = start["B"] as? Data, let challenge = start["c"] as? String,
                  let iterations = (start["i"] as? NSNumber)?.intValue, (1...1_000_000).contains(iterations),
                  let algorithm = start["sp"] as? String, ["s2k", "s2k_fo"].contains(algorithm) else { throw AppleProvisioningError.invalidReply }
            let hash = Array(Self.digest(Data(password.utf8)))
            let input = algorithm == "s2k_fo" ? Array(hash.map { String(format: "%02x", $0) }.joined().utf8) : hash
            let derived = try PKCS5.PBKDF2(password: input, salt: Array(salt), iterations: iterations, keyLength: 32, variant: .sha2(.sha256)).calculate()
            let answer = try srp.answer(username: email, password: Data(derived), salt: salt, server: b)
            let proof = answer.proof
            let finish = try await authenticateRequest(["o": "complete", "u": email, "c": challenge, "M1": Data(proof), "cpd": cpd])
            guard let m2 = finish["M2"] as? Data, let encrypted = finish["spd"] as? Data else { throw AppleProvisioningError.invalidReply }
            try AppleSRP.verify(m2, equals: answer.serverProof)
            let key = answer.key
            let aesKey = Self.mac(key, Data("extra data key:".utf8)), iv = Self.mac(key, Data("extra data iv:".utf8)).prefix(16)
            let plain = try CryptoSwift.AES(key: Array(aesKey), blockMode: CBC(iv: Array(iv)), padding: .pkcs7).decrypt(Array(encrypted))
            let spd = try dictionary(Data(plain))
            guard let dsid = spd["adsid"] as? String, let idms = spd["GsIdmsToken"] as? String else { throw AppleProvisioningError.invalidReply }
            let auth = (finish["Status"] as? [String: Any])?["au"] as? String
            if auth == "trustedDeviceSecondaryAuth" || auth == "secondaryAuth" {
                guard round == 0 else { throw AppleProvisioningError.unsupportedAuthentication }
                try await twoFactor(dsid: dsid, idms: idms, sms: auth == "secondaryAuth", verification: verification)
                continue
            }
            guard auth == nil, let sessionKey = spd["sk"] as? Data, let cookie = spd["c"] as? Data else { throw AppleProvisioningError.unsupportedAuthentication }
            let app = "com.apple.gs.xcode.auth"
            let checksum = Self.mac(sessionKey, Data(("apptokens" + dsid + app).utf8))
            let reply = try await authenticateRequest(["o": "apptokens", "app": [app], "c": cookie, "checksum": checksum,
                "cpd": cpd, "t": idms, "u": dsid])
            guard let et = reply["et"] as? Data, et.count >= 35 else { throw AppleProvisioningError.invalidReply }
            let gcm = GCM(iv: Array(et.subdata(in: 3..<19)), additionalAuthenticatedData: Array(et.prefix(3)), mode: .combined)
            let encryptedToken = Array(et.dropFirst(19))
            let opened = Data(try CryptoSwift.AES(key: Array(sessionKey), blockMode: gcm, padding: .noPadding).decrypt(encryptedToken))
            guard let tokens = try dictionary(opened)["t"] as? [String: Any], let item = tokens[app] as? [String: Any],
                  let authToken = item["token"] as? String, !authToken.isEmpty else { throw AppleProvisioningError.invalidReply }
            accountID = dsid; token = authToken
            let result = try await developer("QH65B2/listTeams.action")
            guard let teams = result["teams"] as? [[String: Any]] else { throw AppleProvisioningError.invalidReply }
            return teams.compactMap { item in
                guard let id = item["teamId"] as? String, let name = item["name"] as? String else { return nil }
                return DeveloperTeam(id: id, name: name)
            }
        }
        throw AppleProvisioningError.unsupportedAuthentication
    }
    private func twoFactor(dsid: String, idms: String, sms: Bool,
                           verification: @Sendable (Bool) async throws -> String) async throws {
        var headers = anisette
        headers["X-Apple-Identity-Token"] = Data((dsid + ":" + idms).utf8).base64EncodedString()
        headers["X-Apple-App-Info"] = "com.apple.gs.xcode.auth"
        let path = sms ? "auth/verify/phone/put?mode=sms" : "auth/verify/trusteddevice"
        let body: [String: Any]? = sms ? ["serverInfo": ["phoneNumber.id": "1"]] : nil
        _ = try await receive(request(try checkedURL("https://gsa.apple.com/" + path), method: sms ? "POST" : "GET", body: body, headers: headers))
        let code = try await verification(sms)
        guard code.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }) else { throw AppleProvisioningError.cancelled }
        headers["security-code"] = code
        let validate = sms ? "auth/verify/phone/securitycode?referrer=/auth/verify/phone/put" : "grandslam/GsService2/validate"
        let payload: [String: Any]? = sms ? ["securityCode.code": code, "serverInfo": ["mode": "sms", "phoneNumber.id": "1"]] : nil
        let data = try await receive(request(try checkedURL("https://gsa.apple.com/" + validate), method: sms ? "POST" : "GET", body: payload, headers: headers))
        if !sms {
            let result = try dictionary(data)
            if let code = (result["ec"] as? NSNumber)?.intValue, code != 0 { throw AppleProvisioningError.rejected(code) }
        }
    }
    private func developer(_ path: String, team: String? = nil, method: String = "POST",
                           body: [String: Any]? = nil, json: Bool = false) async throws -> [String: Any] {
        guard !token.isEmpty, !accountID.isEmpty else { throw AppleProvisioningError.cancelled }
        try await refreshAnisette()
        var headers = anisette
        headers["User-Agent"] = "Xcode"
        headers["X-Apple-I-Identity-Id"] = accountID; headers["X-Apple-GS-Token"] = token
        headers["X-Apple-App-Info"] = "com.apple.gs.xcode.auth"; headers["X-Xcode-Version"] = "27.0 (27A5218g)"
        var parameters: [String: Any] = ["clientId": "XABBG36SBA", "protocolVersion": "QH65B2", "requestId": UUID().uuidString]
        if let team { parameters["teamId"] = team }
        var endpoint = URLComponents(url: service.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !json { endpoint.queryItems = [URLQueryItem(name: "clientId", value: "XABBG36SBA")] }
        let data = try await receive(request(endpoint.url!, method: method,
            body: method == "GET" ? nil : (body ?? parameters), headers: headers, json: json))
        let result = try dictionary(data, json: json)
        if let code = (result["resultCode"] as? NSNumber)?.intValue, code != 0 { throw AppleProvisioningError.rejected(code) }
        if result["errors"] != nil { throw AppleProvisioningError.invalidReply }
        return result
    }
    public func installedApp(team: DeveloperTeam, bundleID: String) async throws -> DeveloperApp {
        let result = try await developer("QH65B2/ios/listAppIds.action", team: team.id)
        guard let rows = result["appIds"] as? [[String: Any]] else { throw AppleProvisioningError.invalidReply }
        let apps: [DeveloperApp] = rows.compactMap { row in
            guard let id = row["appIdId"] as? String, let bundle = row["identifier"] as? String else { return nil }
            return .init(id: id, bundleID: bundle, name: row["name"] as? String ?? bundle)
        }
        return try MemoryCapability.select(apps, installedBundleID: bundleID)
    }
    private func snapshot(_ app: DeveloperApp, team: DeveloperTeam) async throws -> [String: Any] {
        // Restrict path components to developer-portal opaque identifiers.
        guard app.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { throw AppleProvisioningError.invalidReply }
        let path = "v1/bundleIds/" + app.id
        let base = service.appendingPathComponent(path)
        var url = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "include", value: "bundleIdCapabilities,bundleIdCapabilities.capability"), URLQueryItem(name: "teamId", value: team.id)]
        try await refreshAnisette()
        var headers = anisette; headers["User-Agent"] = "Xcode"
        headers["X-Apple-I-Identity-Id"] = accountID; headers["X-Apple-GS-Token"] = token
        headers["X-Apple-App-Info"] = "com.apple.gs.xcode.auth"; headers["X-Xcode-Version"] = "27.0 (27A5218g)"
        let data = try await receive(request(url.url!, method: "GET", headers: headers, json: true))
        return try dictionary(data, json: true)
    }
    public func memoryEnabled(app: DeveloperApp, team: DeveloperTeam) async throws -> Bool {
        MemoryCapability.isEnabled(try await snapshot(app, team: team))
    }
    public func enableMemory(app: DeveloperApp, team: DeveloperTeam, installedBundleID: String) async throws {
        guard app.bundleID == installedBundleID else { throw AppleProvisioningError.missingApp }
        let before = try await snapshot(app, team: team)
        let capabilities = try MemoryCapability.updatedCapabilities(before)
        var editable = try MemoryCapability.preservedAttributes(before, installedBundleID: installedBundleID)
        editable["teamId"] = team.id
        let payload: [String: Any] = ["data": ["id": app.id, "type": "bundleIds", "attributes": editable,
            "relationships": ["bundleIdCapabilities": ["data": capabilities]]]]
        _ = try await developer("v1/bundleIds/" + app.id, team: team.id, method: "PATCH", body: payload, json: true)
        guard try await memoryEnabled(app: app, team: team) else { throw AppleProvisioningError.capabilityNotConfirmed }
    }
}
