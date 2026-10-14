// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import SteamClientKit

/// A made-up PE32/PE32+ image wrapped like SteamStub 3.1: .text,
/// .data, then a .bind section whose entry point follows an encoded stub
/// header. No byte of it comes from a real executable.
struct WrappedImage {
    var appID: UInt32 = 1_654_660
    var codeEncrypted = false
    var is64 = true
    var headerSize = 0xF0
    var bindLast = true
    var overlay: [UInt8] = []

    static let fileAlign = 0x200, sectionAlign = 0x1000
    static let text: [UInt8] = [0x48, 0x83, 0xEC, 0x28, 0xE8, 0, 0, 0, 0, 0x48, 0x83, 0xC4, 0x28, 0xC3]
    static let oep: UInt32 = 0x1000

    func build() -> [UInt8] {
        let optSize = is64 ? 240 : 224
        let headersEnd = 0x40 + 24 + optSize + 40 * 3
        func pad(_ b: inout [UInt8], to n: Int) { if b.count < n { b += [UInt8](repeating: 0, count: n - b.count) } }
        var sections: [(String, UInt32, [UInt8], UInt32)] = []   // name, rva, raw, characteristics
        var textRaw = Self.text; pad(&textRaw, to: Self.fileAlign)
        var dataRaw = [UInt8](repeating: 0x11, count: 0x40); pad(&dataRaw, to: Self.fileAlign)
        // .bind: some stub bytes, the encoded header, then the stub's entry.
        var plain = [UInt8](repeating: 0, count: headerSize)
        SteamStub.put32(&plain, 0, 0x1234_5678)
        SteamStub.put32(&plain, 4, SteamStub.signature)
        SteamStub.put32(&plain, 0x20, Self.oep)
        SteamStub.put32(&plain, 0x38, appID)
        SteamStub.put32(&plain, 0x3C, codeEncrypted ? 0 : 6)
        if codeEncrypted { SteamStub.put32(&plain, 0x48, 0x1000); SteamStub.put32(&plain, 0x50, 0x200) }
        var bindRaw = [UInt8](repeating: 0xCC, count: 0x100) + SteamStub.encodeHeader(plain) + [0x55, 0x48, 0x89, 0xE5, 0xC3]
        pad(&bindRaw, to: (bindRaw.count + Self.fileAlign - 1) / Self.fileAlign * Self.fileAlign)
        let entry = UInt32(0x3000 + 0x100 + headerSize)
        if bindLast {
            sections = [(".text", 0x1000, textRaw, 0x6000_0020), (".data", 0x2000, dataRaw, 0xC000_0040), (".bind", 0x3000, bindRaw, 0x6000_0000)]
        } else {
            sections = [(".text", 0x1000, textRaw, 0x6000_0020), (".bind", 0x2000, bindRaw, 0x6000_0000), (".data", 0x3000, dataRaw, 0xC000_0040)]
        }
        let bindRVA = sections.first { $0.0 == ".bind" }!.1
        let ep = bindLast ? entry : entry - 0x1000

        var b = [UInt8](repeating: 0, count: 0x40)
        b[0] = 0x4D; b[1] = 0x5A; b[0x3C] = 0x40
        b += [0x50, 0x45, 0, 0]
        var coff = [UInt8](repeating: 0, count: 20)
        coff[0] = is64 ? 0x64 : 0x4C; coff[1] = is64 ? 0x86 : 0x01
        coff[2] = 3; coff[16] = UInt8(optSize); coff[18] = 0x22
        b += coff
        var opt = [UInt8](repeating: 0, count: optSize)
        opt[0] = 0x0B; opt[1] = is64 ? 0x02 : 0x01
        SteamStub.put32(&opt, 16, ep)
        SteamStub.put32(&opt, 32, UInt32(Self.sectionAlign))
        SteamStub.put32(&opt, 36, UInt32(Self.fileAlign))
        SteamStub.put32(&opt, 56, 0x4000)
        SteamStub.put32(&opt, 60, UInt32(Self.fileAlign))
        SteamStub.put32(&opt, 64, 0xDEAD_BEEF)
        SteamStub.put32(&opt, is64 ? 108 : 92, 16)
        b += opt
        var raw = UInt32(Self.fileAlign)
        for (name, rva, data, ch) in sections {
            var s = [UInt8](repeating: 0, count: 40)
            for (i, c) in name.utf8.enumerated() { s[i] = c }
            SteamStub.put32(&s, 8, UInt32(data.count)); SteamStub.put32(&s, 12, rva)
            SteamStub.put32(&s, 16, UInt32(data.count)); SteamStub.put32(&s, 20, raw)
            SteamStub.put32(&s, 36, ch)
            b += s
            raw += UInt32(data.count)
        }
        precondition(b.count == headersEnd)
        pad(&b, to: Self.fileAlign)
        for s in sections { b += s.2 }
        _ = bindRVA
        return b + overlay
    }
}

final class SteamStubTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws { dir = try scratchDir("steamstub") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func write(_ name: String, _ bytes: [UInt8]) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
        return url
    }

    func testTheHeaderIsAnXORChain() {
        var plain = [UInt8](repeating: 0, count: 16)
        SteamStub.put32(&plain, 0, 0xA5A5_0001); SteamStub.put32(&plain, 4, SteamStub.signature)
        SteamStub.put32(&plain, 8, 42); SteamStub.put32(&plain, 12, 7)
        let enc = SteamStub.encodeHeader(plain)
        XCTAssertEqual(SteamStub.u32(enc, 0), 0xA5A5_0001, "the key is stored as is")
        XCTAssertEqual(SteamStub.u32(enc, 4), SteamStub.signature ^ 0xA5A5_0001)
        XCTAssertEqual(SteamStub.u32(enc, 8), 42 ^ SteamStub.u32(enc, 4), "each dword is XORed with the stored one before it")
        XCTAssertEqual(SteamStub.decodeHeader(enc), plain)
    }

    func testInspectReadsA31x64Stub() throws {
        let url = try write("Game.exe", WrappedImage().build())
        let info = try XCTUnwrap(SteamStub.inspect(url))
        XCTAssertEqual(info, .init(variant: "3.1", arch: "x64", appID: 1_654_660, originalEntryPoint: 0x1000, encrypted: false, flags: 6))
        XCTAssertNil(info.unsupported)
        XCTAssertEqual(info.label, "SteamStub 3.1 x64")
    }

    func testInspectAndUnwrapAnUnencrypted31x86Stub() throws {
        let original = WrappedImage(is64: false).build()
        let src = try write("Game32.exe", original)
        let info = try XCTUnwrap(SteamStub.inspect(src))
        XCTAssertEqual(info, .init(variant: "3.1", arch: "x86", appID: 1_654_660,
                                   originalEntryPoint: 0x1000, encrypted: false, flags: 6))
        XCTAssertNil(info.unsupported)

        let dst = dir.appendingPathComponent("Game32.unwrapped.exe")
        try SteamStub.unwrap(src, to: dst)
        XCTAssertNil(SteamStub.inspect(dst))
        let out = [UInt8](try Data(contentsOf: dst))
        XCTAssertEqual(Array(out[0x200..<0x200 + WrappedImage.text.count]), WrappedImage.text)
        let h = try FileHandle(forReadingFrom: dst)
        let pe = try PEImage.read(h)
        try h.close()
        XCTAssertFalse(pe.is64)
        XCTAssertEqual(pe.entryPoint, WrappedImage.oep)
        XCTAssertEqual(pe.sections.map(\.name), [".text", ".data"])
        XCTAssertEqual([UInt8](try Data(contentsOf: src)), original, "never change the owned original")
    }

    func testMalformedEncrypted31x86BoundsAreNeverModified() throws {
        var malformed = encryptedImage()
        changeHeader(&malformed) { SteamStub.put32(&$0, 0x50, 0x201) }
        let src = try write("Game32-protected.exe", malformed)
        let info = try XCTUnwrap(SteamStub.inspect(src))
        XCTAssertEqual(info.arch, "x86")
        XCTAssertEqual(info.appID, 1_144_400)
        XCTAssertTrue(info.encrypted)
        XCTAssertNil(info.unsupported)
        let dest = dir.appendingPathComponent("unwrapped.exe")
        XCTAssertThrowsError(try SteamStub.unwrap(src, to: dest))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    }

    /// AES bytes produced with OpenSSL AES-256-CBC/ECB -nopad, never with
    /// Playport's decryptor. The last plaintext block looks like PKCS#7 padding.
    private static let cipher = Array(hexString: "74cb883cb1f489bc90d2aa090847090fd54de6b9330b4658dade23f55784d9e0f8cc9e1edf2999fa6a04f9d24a1ce918ee202eb49847460c11d2370934ce4cc8b82f50dd2de084283b3b55f545e165a819c5c23dd868bd77d0ba1b93754d175390a1ddb0a8f0da876a6306a3988321096497f90021bff77e125428d07b1ba2189de9526bc16306360aad8b62995795b9d456a859e2815d99a5b1023b3315d008f989062153b2a32b9b3a305bd4b8cee6c148aa94ddb8aabeaa79d7ea2b4d60eaa398a46fe349d17edb11de4b1845f56a7561ef70c215930c317a31e33505153861c573e29dd1bce9aaae10ca56ecaf2402f8f4dc65bf3c63b8986d7abceec1d9a97b0dc2aa898e9f252823c81214077680f86e8cab8cfead78900ef796202ca45cb5064d6dcef198d2bdbb328ec4a803efbcfd15c7d1b76b9718aa1706b6c4793af174cd454992a6024fe8321f5069008d485a4bbb95e5d37733c0f27e97335327fb564ad30fd3c2e249e1a5fc89cdca02aa0d60242d618d388967ef53886a88fb7d05e8402f831c955ac99c5441c70b5fe86a46e9f258973bfe92c16c53ebe13bfc06bdebe8459d058f5cb48575fb8c2d74c9d013616d16204e58b9a6380c1163bbd02b2d5a1182c5e04ea6cda37c8e6e86a066f155c80762dc448424fc40c52509c339351c355eb223c3dd71b1f0c3933fad886bfd61a21335deb64e6798fca195470e03b17eee7a7a1e09327082d2")
    private static let encryptedIV = Array(hexString: "5a6e045708fb7196f02e553d02c3a692")
    private static let plaintext = [UInt8]([0x55, 0x8b, 0xec, 0x83, 0xec, 0x10, 0x33, 0xc0, 0xc9, 0xc3])
        + (0..<486).map { UInt8(($0 * 37 + 11) & 255) } + [UInt8](repeating: 16, count: 16)

    private func changeHeader(_ bytes: inout [UInt8], bindLast: Bool = true, _ change: (inout [UInt8]) -> Void) {
        let offset = bindLast ? 0x700 : 0x500
        var head = SteamStub.decodeHeader(Array(bytes[offset..<offset + 0xF0]))
        change(&head)
        bytes.replaceSubrange(offset..<offset + 0xF0, with: SteamStub.encodeHeader(head))
    }

    private func encryptedImage(bindLast: Bool = true, overlay: [UInt8] = []) -> [UInt8] {
        var bytes = WrappedImage(appID: 1_144_400, codeEncrypted: true, is64: false,
                                 bindLast: bindLast, overlay: overlay).build()
        bytes.replaceSubrange(0x200..<0x400, with: Self.cipher.dropFirst(16))
        changeHeader(&bytes, bindLast: bindLast) { head in
            head.replaceSubrange(0x58..<0x78, with: (0..<32).map { UInt8($0) })
            head.replaceSubrange(0x78..<0x88, with: Self.encryptedIV)
            head.replaceSubrange(0x88..<0x98, with: Self.cipher.prefix(16))
        }
        return bytes
    }

    func testDecryptsEncryptedX86AndPreservesPaddingShapedCode() throws {
        let original = encryptedImage()
        let src = try write("encrypted.exe", original)
        let dst = dir.appendingPathComponent("decrypted.exe")
        let info = try SteamStub.unwrap(src, to: dst)
        XCTAssertTrue(info.encrypted)
        XCTAssertEqual(info.appID, 1_144_400)
        let out = [UInt8](try Data(contentsOf: dst))
        XCTAssertEqual(Array(out[0x200..<0x400]), Self.plaintext)
        XCTAssertEqual(Array(out[0x400..<0x600]), Array(original[0x400..<0x600]))
        XCTAssertEqual(out.count, 0x600)
        XCTAssertNil(SteamStub.inspect(dst))
        XCTAssertEqual(SteamStub.u32(out, 0x40 + 24 + 16), 0x1000)
        XCTAssertEqual([UInt8](try Data(contentsOf: src)), original)
    }

    func testEncryptedCodeWithKeptBindAndOverlay() throws {
        for bindLast in [false, true] {
            let original = encryptedImage(bindLast: bindLast, overlay: [7, 8, 9])
            let src = try write("overlay-\(bindLast).exe", original)
            let dst = dir.appendingPathComponent("out-\(bindLast).exe")
            try SteamStub.unwrap(src, to: dst)
            let out = [UInt8](try Data(contentsOf: dst))
            XCTAssertEqual(out.count, original.count)
            XCTAssertEqual(out.suffix(3), [7, 8, 9])
            XCTAssertEqual(Array(out[0x200..<0x400]), Self.plaintext)
        }
    }

    func testEncryptedRemovalIsReversibleIdempotentAndVerifiedAgainstOriginal() async throws {
        let original = encryptedImage()
        let src = try write("owned/Game.exe", original)
        let root = src.deletingLastPathComponent()
        XCTAssertEqual(try SteamStub.remove(in: root).first?.removed, true)
        XCTAssertEqual(try SteamStub.remove(in: root).first?.removed, true)
        let kept = src.appendingPathExtension("orig")
        XCTAssertEqual([UInt8](try Data(contentsOf: kept)), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept.appendingPathExtension("orig").path))
        let list = dir.appendingPathComponent("owned-sums")
        try "\(SHA256Stream.hash(original).hex)  Game.exe\n".write(to: list, atomically: true, encoding: .utf8)
        let checked = try await TitleInstaller.verifySHA256List(dir: root, list: list)
        XCTAssertEqual(checked.bad, [])
        XCTAssertEqual(try SteamStub.restore(in: root), 1)
        XCTAssertEqual([UInt8](try Data(contentsOf: src)), original)
    }

    func testInvalidEncryptedSectionsNeverChangeSourceOrExistingDestination() throws {
        for kind in 0..<7 {
            var invalid = encryptedImage()
            changeHeader(&invalid) { h in
                if kind == 0 { SteamStub.put32(&h, 0x48, 0x2000) } // non-executable .data
                if kind == 1 { SteamStub.put32(&h, 0x48, 0x3000) } // wrapper itself
                if kind == 2 { SteamStub.put32(&h, 0x50, 0) }
                if kind == 3 { SteamStub.put32(&h, 0x50, 0x201) }
                if kind == 4 { SteamStub.put32(&h, 0x54, UInt32.max) }
                if kind == 5 { SteamStub.put32(&h, 0x20, 0x3000) } // original entry in wrapper
                if kind == 6 { SteamStub.put32(&h, 0x48, 0x1001) } // section interior, unknown layout
            }
            let src = try write("invalid-\(kind).exe", invalid)
            let dst = try write("existing-\(kind).exe", [1, 2, 3])
            XCTAssertThrowsError(try SteamStub.unwrap(src, to: dst))
            XCTAssertEqual([UInt8](try Data(contentsOf: src)), invalid)
            XCTAssertEqual([UInt8](try Data(contentsOf: dst)), [1, 2, 3])
        }
    }

    func testUnwrapRefusesTheSameFileAndTruncatedPEHeaders() throws {
        let original = encryptedImage()
        let src = try write("same.exe", original)
        XCTAssertThrowsError(try SteamStub.unwrap(src, to: src))
        XCTAssertEqual([UInt8](try Data(contentsOf: src)), original)
        var invalid = original
        invalid[0x40 + 20] = 0; invalid[0x40 + 21] = 0
        XCTAssertNil(SteamStub.inspect(try write("short-opt.exe", invalid)))
    }

    func testWrapperTLSIsRejectedAndOriginalTLSIsKept() throws {
        for callback in [UInt32(0x4031F0), UInt32(0x4010F0)] {
            var b = encryptedImage()
            SteamStub.put32(&b, 0x40 + 24 + 28, 0x400000) // PE32 image base
            SteamStub.put32(&b, 0x40 + 24 + 96 + 9 * 8, 0x2000)
            SteamStub.put32(&b, 0x40 + 24 + 96 + 9 * 8 + 4, 24)
            SteamStub.put32(&b, 0x400 + 12, 0x402040)
            SteamStub.put32(&b, 0x440, callback)
            SteamStub.put32(&b, 0x444, 0)
            let src = try write("tls-\(callback).exe", b)
            let dst = dir.appendingPathComponent("tls-out-\(callback).exe")
            if callback == 0x4031F0 {
                XCTAssertThrowsError(try SteamStub.unwrap(src, to: dst))
                XCTAssertFalse(FileManager.default.fileExists(atPath: dst.path))
            } else {
                try SteamStub.unwrap(src, to: dst)
                XCTAssertEqual(Array([UInt8](try Data(contentsOf: dst))[0x400..<0x600]), Array(b[0x400..<0x600]))
            }
            XCTAssertEqual([UInt8](try Data(contentsOf: src)), b)
        }
    }

    func testAnImageWithoutAStubIsNone() throws {
        let plain = try write("plain.exe", peImage(machine: 0x8664, tag: "no stub"))
        XCTAssertNil(SteamStub.inspect(plain))
        let text = try write("text.exe", Array("MZ but not really".utf8))
        XCTAssertNil(SteamStub.inspect(text))
        var bad = WrappedImage().build()
        bad[0x704] ^= 0xFF   // the encoded signature (.bind at 0x600, the header 0x100 into it)
        XCTAssertNil(SteamStub.inspect(try write("broken.exe", bad)))
    }

    func testUnwrapRestoresTheEntryPointAndDropsTheLastBindSection() throws {
        let src = try write("Game.exe", WrappedImage().build())
        let dst = dir.appendingPathComponent("Game.unwrapped.exe")
        try SteamStub.unwrap(src, to: dst)
        XCTAssertNil(SteamStub.inspect(dst))
        let h = try FileHandle(forReadingFrom: dst)
        let pe = try PEImage.read(h)
        try h.close()
        XCTAssertEqual(pe.entryPoint, 0x1000)
        XCTAssertEqual(pe.sections.map(\.name), [".text", ".data"])
        let out = [UInt8](try Data(contentsOf: dst))
        XCTAssertEqual(out.count, 3 * WrappedImage.fileAlign, "the headers, .text and .data; .bind is gone")
        XCTAssertEqual(Array(out[0x200..<0x200 + WrappedImage.text.count]), WrappedImage.text, "the code is untouched")
        XCTAssertEqual(SteamStub.u32(out, 0x40 + 24 + 56), 0x3000, "SizeOfImage ends after .data")
        XCTAssertEqual(SteamStub.u32(out, 0x40 + 24 + 64), 0, "CheckSum cleared")
        XCTAssertNotNil(SteamStub.inspect(src), "the source is not changed")
    }

    func testABindSectionThatIsNotLastStaysInPlace() throws {
        let src = try write("Game.exe", WrappedImage(bindLast: false).build())
        let dst = dir.appendingPathComponent("out.exe")
        try SteamStub.unwrap(src, to: dst)
        let h = try FileHandle(forReadingFrom: dst)
        let pe = try PEImage.read(h)
        try h.close()
        XCTAssertEqual(pe.entryPoint, 0x1000)
        XCTAssertEqual(pe.sections.map(\.name), [".text", ".bind", ".data"])
        XCTAssertEqual(try Data(contentsOf: dst).count, try Data(contentsOf: src).count)
    }

    func testAnOverlayAfterBindKeepsTheSection() throws {
        let src = try write("Game.exe", WrappedImage(overlay: [UInt8](repeating: 7, count: 100)).build())
        let dst = dir.appendingPathComponent("out.exe")
        try SteamStub.unwrap(src, to: dst)
        XCTAssertEqual(try Data(contentsOf: dst).count, try Data(contentsOf: src).count, "the overlay stays where it was")
    }

    func testWhatIsNotCheckedOnARealExecutableIsRefused() throws {
        let enc = try write("enc.exe", WrappedImage(codeEncrypted: true).build())
        XCTAssertEqual(SteamStub.inspect(enc)?.unsupported, "SteamStub 3.1 x64 with encrypted code is not supported yet")
        let v30 = try write("v30.exe", WrappedImage(headerSize: 0xD0).build())
        XCTAssertEqual(SteamStub.inspect(v30)?.variant, "3.0")
        XCTAssertNotNil(SteamStub.inspect(v30)?.unsupported)
        let x86 = try write("x86.exe", WrappedImage(is64: false).build())
        XCTAssertEqual(SteamStub.inspect(x86)?.arch, "x86")
        XCTAssertThrowsError(try SteamStub.unwrap(enc, to: dir.appendingPathComponent("x.exe")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("x.exe").path))
    }

    func testRemoveAndRestoreInAGameFolder() throws {
        let root = dir.appendingPathComponent("Game")
        let wrapped = WrappedImage().build()
        _ = try write("Game/Launcher.exe", peImage(machine: 0x8664, tag: "launcher"))
        _ = try write("Game/Bin/Game-Shipping.exe", wrapped)
        _ = try write("Game/Bin/Other.exe", WrappedImage(codeEncrypted: true).build())
        let sites = try SteamStub.remove(in: root)
        XCTAssertEqual(sites.map(\.path), ["Bin/Game-Shipping.exe", "Bin/Other.exe"])
        XCTAssertEqual(sites.map(\.removed), [true, false], "an unsupported stub is left alone")
        XCTAssertEqual([UInt8](try Data(contentsOf: root.appendingPathComponent("Bin/Game-Shipping.exe.orig"))), wrapped)
        XCTAssertNil(SteamStub.inspect(root.appendingPathComponent("Bin/Game-Shipping.exe")))
        // Again: nothing to do, and the site still reads as the game's stub.
        let again = try SteamStub.remove(in: root)
        XCTAssertEqual(again.first?.info.appID, 1_654_660)
        XCTAssertEqual(again.first?.removed, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Bin/Game-Shipping.exe.orig.orig").path))

        XCTAssertEqual(try SteamStub.restore(in: root), 1)
        XCTAssertEqual([UInt8](try Data(contentsOf: root.appendingPathComponent("Bin/Game-Shipping.exe"))), wrapped)
        XCTAssertEqual(SteamStub.sites(in: root).map(\.removed), [false, false])
    }

    func testVerifySeesTheKeptExecutable() async throws {
        let root = dir.appendingPathComponent("Game")
        let wrapped = WrappedImage().build()
        _ = try write("Game/Bin/Game-Shipping.exe", wrapped)
        let list = dir.appendingPathComponent("sums")
        try "\(SHA256Stream.hash(wrapped).hex)  Bin/Game-Shipping.exe\n".write(to: list, atomically: true, encoding: .utf8)
        try SteamStub.remove(in: root)
        let r = try await TitleInstaller.verifySHA256List(dir: root, list: list)
        XCTAssertEqual(r.bad, [])
        XCTAssertEqual(r.unlisted, [])
    }

    /// The real check: an executable SteamStub wrapped, when one is given
    /// (`STEAMSTUB_SAMPLE=<exe>`). Its bytes never enter the repository.
    func testARealSample() throws {
        guard let path = ProcessInfo.processInfo.environment["STEAMSTUB_SAMPLE"] else {
            throw XCTSkip("STEAMSTUB_SAMPLE is not set")
        }
        let src = URL(fileURLWithPath: path)
        let info = try XCTUnwrap(SteamStub.inspect(src))
        print("sample: \(info.label), app \(info.appID), OEP \(String(info.originalEntryPoint, radix: 16)), encrypted \(info.encrypted), flags \(info.flags)")
        XCTAssertNil(info.unsupported)
        let dst = dir.appendingPathComponent("sample.exe")
        try SteamStub.unwrap(src, to: dst)
        XCTAssertNil(SteamStub.inspect(dst))
        let h = try FileHandle(forReadingFrom: dst)
        let pe = try PEImage.read(h)
        try h.close()
        XCTAssertEqual(pe.entryPoint, info.originalEntryPoint)
        XCTAssertFalse(pe.sections.contains { $0.name == ".bind" })
        print("sample: unwrapped \(try Data(contentsOf: src).count) -> \(try Data(contentsOf: dst).count) bytes, sections \(pe.sections.map(\.name))")
    }
}
