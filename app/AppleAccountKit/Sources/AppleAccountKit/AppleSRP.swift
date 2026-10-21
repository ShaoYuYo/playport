// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import BigInt
import CryptoSwift

/// GrandSlam SRP-6a: RFC 5054's fixed 2048-bit group, SHA-256 and binary password.
/// Protocol formulae also cross-checked against adam-fowler/swift-srp (Apache-2.0).
/// Account setup only; no cryptographic work is performed on the game render path.
struct AppleSRP {
    static let modulus = BigUInt("AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC3192943DB56050A37329CBB4A099ED8193E0757767A13DD52312AB4B03310DCD7F48A9DA04FD50E8083969EDB767B0CF6095179A163AB3661A05FBD5FAAAE82918A9962F0B93B855F97993EC975EEAA80D740ADBF4FF747359D041D5C33EA71D281E446B14773BCA97B43A23FB801676BD207A436C6481F1D2B9078717461A5B9D32E688F87748544523B524B0D57D5EA77A2775D2ECFA032CFBDBF52FB3786160279004E57AE6AF874E7303CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DBFBB694B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F9E4AFF73", radix: 16)!
    let secret: BigUInt
    let publicKey: Data
    init(privateKey: Data? = nil) {
        var rng = SystemRandomNumberGenerator()
        let bytes = privateKey ?? Data((0..<32).map { _ in UInt8.random(in: 0...255, using: &rng) })
        // Never accept a zero exponent, including a deterministic test input.
        secret = max(BigUInt(bytes), 1)
        publicKey = BigUInt(2).power(secret, modulus: Self.modulus).serialize()
    }
    static func pad(_ n: BigUInt) -> Data {
        let bytes = n.serialize()
        return Data(repeating: 0, count: max(0, 256 - bytes.count)) + bytes
    }
    static func hash(_ value: Data) -> Data { Data(Array(value).sha256()) }
    func answer(username: String, password: Data, salt: Data, server: Data) throws -> (key: Data, proof: Data, serverProof: Data) {
        guard !server.isEmpty, server.count <= 256, !salt.isEmpty, salt.count <= 1024 else { throw AppleProvisioningError.invalidReply }
        let n = Self.modulus, b = BigUInt(server)
        guard b > 0, b < n else { throw AppleProvisioningError.invalidReply }
        let paddedB = Self.pad(b), paddedG = Self.pad(2)
        let u = BigUInt(Self.hash(Self.pad(BigUInt(publicKey)) + paddedB))
        guard u != 0 else { throw AppleProvisioningError.invalidReply }
        let x = BigUInt(Self.hash(salt + Self.hash(Data([0x3a]) + password)))
        let k = BigUInt(Self.hash(Self.pad(n) + paddedG))
        let subtrahend = (k * BigUInt(2).power(x, modulus: n)) % n
        let base = (b + n - subtrahend) % n
        guard base != 0 else { throw AppleProvisioningError.invalidReply }
        let shared = base.power(secret + u * x, modulus: n)
        // GSA hashes the minimal big-endian S, not its group-width padding.
        let key = Self.hash(shared.serialize())
        let xor = Data(zip(Self.hash(Self.pad(n)), Self.hash(paddedG)).map { $0 ^ $1 })
        let proof = Self.hash(xor + Self.hash(Data(username.utf8)) + salt + publicKey + server + key)
        return (key, proof, Self.hash(publicKey + proof + key))
    }
    static func verify(_ received: Data, equals expected: Data) throws {
        guard received.count == 32, expected.count == 32 else { throw AppleProvisioningError.invalidReply }
        let difference = zip(received, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
        guard difference == 0 else { throw AppleProvisioningError.invalidReply }
    }
}
