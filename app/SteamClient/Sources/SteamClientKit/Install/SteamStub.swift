// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Steam's DRM wrapper (SteamStub) taken off a game's executable, and put
/// back (docs/plans/finished.md#steam-for-games, phase 2). A wrapped
/// executable starts in a `.bind` section whose stub checks for a running
/// Steam client before it jumps to the game's own entry point; with no Steam
/// on the phone the game exits there.
///
/// Written from the format: the stub header sits just before the entry point
/// and is XOR-chained dword by dword, its first dword being the key; a
/// variant 3 header decrypts to the signature 0xC0DEC0DF. The header names
/// the original entry point, the app ID and, when the stub also encrypts the
/// game's code, the code section's AES key. Variant 3.1 x86 code sections can be decrypted with the file's own key. The x64 path
/// was validated with En Garde! (docs/evidence/2026-09-27-gbe-steam-api-build.md);
/// x86 shares its 3.1 header offsets and is tested with independently encrypted PE32 fixtures.
/// Encrypted x64 code and older variants remain unsupported and are left alone.
///
/// Like SteamAPISwap, the game's executable is kept as `<name>.orig` and a
/// copy without the stub takes its place (an APFS clone plus a few header
/// bytes), and `restore` puts the game's back; verify and repair see the kept
/// original.
public enum SteamStub {
    public static let signature: UInt32 = 0xC0DE_C0DF

    public struct Info: Sendable, Equatable {
        /// "3.1" or "3.0", from the header's size.
        public var variant: String
        /// "x64" or "x86".
        public var arch: String
        public var appID: UInt32
        /// The game's own entry point (an RVA).
        public var originalEntryPoint: UInt32
        /// The stub also encrypts the game's code section.
        public var encrypted: Bool
        public var flags: UInt32

        /// What Playport can take off; nil when it can, else why not.
        public var unsupported: String? {
            if variant != "3.1" { return "SteamStub \(variant) \(arch) is not supported yet" }
            if encrypted {
                if arch != "x86" { return "SteamStub \(variant) \(arch) with encrypted code is not supported yet" }
                if flags & 0x4 != 0 { return "SteamStub \(variant) \(arch) has inconsistent encryption fields" }
            }
            return nil
        }

        public var label: String { "SteamStub \(variant) \(arch)" }
    }

    /// An executable's SteamStub, read from its headers and the stub header
    /// only; nil when it has none.
    public static func inspect(_ url: URL) -> Info? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let pe = try? PEImage.read(h), let bind = pe.section(containingRVA: pe.entryPoint),
              bind.name == ".bind" else { return nil }
        let epOffset = UInt64(bind.rawPointer) + UInt64(pe.entryPoint - bind.virtualAddress)
        for (size, variant) in [(0xF0, "3.1"), (0xD0, "3.0")] where epOffset >= UInt64(size) {
            let delta = UInt64(pe.entryPoint) - UInt64(bind.virtualAddress)
            guard delta >= UInt64(size), delta < UInt64(bind.rawSize) else { continue }
            guard (try? h.seek(toOffset: epOffset - UInt64(size))) != nil,
                  let raw = try? h.read(upToCount: size), raw.count == size else { continue }
            let head = decodeHeader([UInt8](raw))
            guard u32(head, 4) == signature else { continue }
            let arch = pe.is64 ? "x64" : "x86"
            // SteamStub 3.1 uses the same 0xF0-byte header field offsets for
            // PE32 and PE32+. Earlier variants are identified but not unwrapped.
            guard variant == "3.1" else {
                return Info(variant: variant, arch: arch, appID: 0, originalEntryPoint: 0, encrypted: true, flags: 0)
            }
            let oep = u64(head, 0x20)
            let flags = u32(head, 0x3C)
            // NoEncryption is bit 2. A contradictory nonzero code region is
            // rejected, while the x86 encrypted layout is validated before writing.
            let encrypted = flags & 0x4 == 0 || u64(head, 0x48) != 0 || u64(head, 0x50) != 0
            return Info(variant: variant, arch: arch, appID: u32(head, 0x38),
                        originalEntryPoint: UInt32(exactly: oep) ?? 0,
                        encrypted: encrypted, flags: flags)
        }
        return nil
    }

    /// The header's dwords XOR-chained back: each is XORed with the one before
    /// it as stored, the first being the key.
    static func decodeHeader(_ raw: [UInt8]) -> [UInt8] {
        var out = raw
        var key = u32(raw, 0)
        for i in stride(from: 4, to: raw.count - 3, by: 4) {
            let stored = u32(raw, i)
            put32(&out, i, stored ^ key)
            key = stored
        }
        return out
    }

    /// The inverse of decodeHeader, for building test images.
    static func encodeHeader(_ plain: [UInt8]) -> [UInt8] {
        var out = plain
        var prev = u32(plain, 0)
        for i in stride(from: 4, to: plain.count - 3, by: 4) {
            let stored = u32(plain, i) ^ prev
            put32(&out, i, stored)
            prev = stored
        }
        return out
    }

    // MARK: unwrapping

    /// Writes `source` without its stub to `dest`: the entry point is the
    /// game's own again, and the `.bind` section is dropped when it is the
    /// file's last and nothing else points into it (else it stays, unused).
    @discardableResult
    public static func unwrap(_ source: URL, to dest: URL) throws -> Info {
        guard let info = inspect(source) else { throw SteamError.unsupported("\(source.lastPathComponent) has no SteamStub") }
        if let why = info.unsupported { throw SteamError.unsupported(why) }
        guard source.standardizedFileURL.resolvingSymlinksInPath() != dest.standardizedFileURL.resolvingSymlinksInPath() else {
            throw SteamError.unsupported("the unwrapped destination must differ from the owned original")
        }
        let h = try FileHandle(forReadingFrom: source)
        defer { try? h.close() }
        let pe = try PEImage.read(h)
        guard let bind = pe.section(containingRVA: pe.entryPoint),
              let originalSection = pe.section(containingRVA: info.originalEntryPoint),
              originalSection.executable, originalSection != bind else {
            throw SteamError.unsupported("the original entry point is not in an executable section")
        }
        guard try !pe.tlsReferences(bind, in: h) else {
            throw SteamError.unsupported("SteamStub TLS callbacks into the wrapper are not supported")
        }
        // Validate and decrypt completely before creating or replacing any file.
        let code = info.encrypted ? try decryptX86Code(h, pe: pe, bind: bind, info: info) : nil
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: source, to: dest)   // a clone on APFS
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: dest) } }
        let out = try FileHandle(forUpdating: dest)
        defer { try? out.close() }
        if let code {
            try out.seek(toOffset: code.offset)
            try out.write(contentsOf: Data(code.bytes))
        }
        try write32(out, pe.optionalHeader + 16, info.originalEntryPoint)
        try write32(out, pe.optionalHeader + 64, 0)   // CheckSum: not checked for an executable
        let size = try out.seekToEnd()
        let bindEnd = UInt64(bind.rawPointer) + UInt64(bind.rawSize)
        let last = pe.sections.last == bind
        let referenced = pe.dataDirectories.contains { $0.rva != 0 && $0.rva >= bind.virtualAddress
            && UInt64($0.rva) < UInt64(bind.virtualAddress) + UInt64(max(bind.virtualSize, bind.rawSize)) }
        if last, bindEnd == size, !referenced, bind.rawPointer > 0 {
            // Drop the section: its header, the count, SizeOfImage and its bytes.
            try write16(out, pe.coffHeader + 2, UInt16(pe.sections.count - 1))
            try out.seek(toOffset: UInt64(pe.sectionTable + 40 * (pe.sections.count - 1)))
            try out.write(contentsOf: Data(count: 40))
            let prev = pe.sections[pe.sections.count - 2]
            let end = UInt64(prev.virtualAddress) + UInt64(max(prev.virtualSize, prev.rawSize))
            let align = UInt64(max(pe.sectionAlignment, 1))
            guard let imageSize = UInt32(exactly: (end + align - 1) / align * align) else {
                throw SteamError.unsupported("the unwrapped PE image size is invalid")
            }
            try write32(out, pe.optionalHeader + 56, imageSize)
            try out.truncate(atOffset: UInt64(bind.rawPointer))
        }
        complete = true
        return info
    }

    private static func decryptX86Code(_ h: FileHandle, pe: PEImage, bind: PEImage.Section, info: Info)
        throws -> (offset: UInt64, bytes: [UInt8]) {
        guard !pe.is64, info.variant == "3.1", info.flags & 0x4 == 0 else {
            throw SteamError.unsupported("unsupported SteamStub encrypted-code layout")
        }
        let delta = UInt64(pe.entryPoint) - UInt64(bind.virtualAddress)
        guard delta >= 0xF0, delta < UInt64(bind.rawSize) else {
            throw SteamError.unsupported("SteamStub header lies outside its raw section")
        }
        try h.seek(toOffset: UInt64(bind.rawPointer) + delta - 0xF0)
        guard let raw = try h.read(upToCount: 0xF0), raw.count == 0xF0 else {
            throw SteamError.unsupported("truncated SteamStub code header")
        }
        let head = decodeHeader([UInt8](raw))
        guard u32(head, 4) == signature, u64(head, 0x20) == UInt64(info.originalEntryPoint),
              u32(head, 0x38) == info.appID, u32(head, 0x3C) == info.flags,
              let rva = UInt32(exactly: u64(head, 0x48)),
              let section = pe.section(containingRVA: rva), section != bind,
              section.executable, section.virtualAddress == rva else {
            throw SteamError.unsupported("invalid SteamStub encrypted-code section")
        }
        let count = u64(head, 0x50), fileSize = try h.seekToEnd()
        let offset = UInt64(section.rawPointer), endRVA = UInt64(rva) + count
        let headersEnd = UInt64(pe.sectionTable + 40 * pe.sections.count)
        let overlaps = pe.sections.contains { other in
            other != section && other.rawSize != 0 && offset < UInt64(other.rawPointer) + UInt64(other.rawSize)
                && UInt64(other.rawPointer) < offset + count
        }
        guard count > 0, count % 16 == 0, count <= 128 * 1024 * 1024,
              count <= UInt64(section.rawSize), offset >= headersEnd, !overlaps,
              offset <= fileSize, count <= fileSize - offset,
              UInt64(info.originalEntryPoint) >= UInt64(rva), UInt64(info.originalEntryPoint) < endRVA else {
            throw SteamError.unsupported("invalid SteamStub encrypted-code bounds")
        }
        try h.seek(toOffset: offset)
        guard let body = try h.read(upToCount: Int(count)), body.count == Int(count) else {
            throw SteamError.unsupported("truncated SteamStub encrypted code")
        }
        let aes = try AES256Decryptor(key: Array(head[0x58..<0x78]))
        var iv = Array(head[0x78..<0x88]); aes.decryptBlock(&iv)
        // The header holds the first ciphertext block. Restore it before CBC,
        // then write only the declared code length; the final extra block is
        // cipher continuation, not an instruction or PKCS#7 padding.
        let cipher = Array(head[0x88..<0x98]) + body
        let plain = try aes.decryptCBCUnpadded(cipher[...], iv: iv)
        return (offset, Array(plain.prefix(Int(count))))
    }

    // MARK: in a game's folder

    /// A wrapped executable under a game's folder.
    public struct Site: Sendable, Equatable {
        public var path: String
        public var info: Info
        /// The game's executable is kept as `<path>.orig` and the unwrapped copy is in its place.
        public var removed: Bool
    }

    /// Every executable under `root` that carries (or, kept as `.orig`, carried) SteamStub.
    public static func sites(in root: URL) -> [Site] {
        let files = TitleInstaller.regularFiles(under: root)
        let present = Set(files)
        return files.compactMap { path in
            guard path.lowercased().hasSuffix(".exe") else { return nil }
            let removed = present.contains(path + SteamAPISwap.originalSuffix)
            let url = root.appendingPathComponent(removed ? path + SteamAPISwap.originalSuffix : path)
            return inspect(url).map { Site(path: path, info: $0, removed: removed) }
        }
    }

    /// Takes the stub off every wrapped executable Playport can unwrap (the
    /// game's kept as `.orig`). Returns every site, removed or not.
    @discardableResult
    public static func remove(in root: URL) throws -> [Site] {
        var out: [Site] = []
        for var site in sites(in: root) {
            if !site.removed, site.info.unsupported == nil {
                let exe = try InstallFS.resolveInside(root, site.path, createParents: false)
                let tmp = exe.deletingLastPathComponent().appendingPathComponent(".\(exe.lastPathComponent).unwrapped")
                try unwrap(exe, to: tmp)
                guard rename(exe.path, exe.path + SteamAPISwap.originalSuffix) == 0 else {
                    try? FileManager.default.removeItem(at: tmp)
                    throw SteamError.transport("cannot keep \(site.path) as .orig (errno \(errno))")
                }
                guard rename(tmp.path, exe.path) == 0 else { throw SteamError.transport("cannot place the unwrapped \(site.path) (errno \(errno))") }
                site.removed = true
            }
            out.append(site)
        }
        return out
    }

    /// Puts every kept executable back. Returns how many.
    @discardableResult
    public static func restore(in root: URL) throws -> Int {
        var n = 0
        for site in sites(in: root) where site.removed {
            let exe = try InstallFS.resolveInside(root, site.path, createParents: false)
            guard rename(exe.path + SteamAPISwap.originalSuffix, exe.path) == 0 else {
                throw SteamError.transport("cannot restore \(site.path) (errno \(errno))")
            }
            n += 1
        }
        return n
    }

    // MARK: bytes

    static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }

    static func u64(_ b: [UInt8], _ o: Int) -> UInt64 { UInt64(u32(b, o)) | UInt64(u32(b, o + 4)) << 32 }

    static func put32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        for i in 0..<4 { b[o + i] = UInt8(truncatingIfNeeded: v >> (8 * i)) }
    }

    static func write32(_ h: FileHandle, _ offset: Int, _ v: UInt32) throws {
        var b = [UInt8](repeating: 0, count: 4)
        put32(&b, 0, v)
        try h.seek(toOffset: UInt64(offset))
        try h.write(contentsOf: Data(b))
    }

    static func write16(_ h: FileHandle, _ offset: Int, _ v: UInt16) throws {
        try h.seek(toOffset: UInt64(offset))
        try h.write(contentsOf: Data([UInt8(v & 0xff), UInt8(v >> 8)]))
    }
}

/// The parts of a PE image's headers the unwrapper reads.
struct PEImage {
    struct Section: Equatable {
        var name: String
        var virtualSize: UInt32
        var virtualAddress: UInt32
        var rawSize: UInt32
        var rawPointer: UInt32
        var characteristics: UInt32
        var executable: Bool { characteristics & 0x2000_0000 != 0 }
    }

    struct Directory { var rva: UInt32; var size: UInt32 }

    var coffHeader: Int
    var optionalHeader: Int
    var sectionTable: Int
    var is64: Bool
    var entryPoint: UInt32
    var sectionAlignment: UInt32
    var imageBase: UInt64
    var sections: [Section]
    var dataDirectories: [Directory]

    func section(containingRVA rva: UInt32) -> Section? {
        sections.first { rva >= $0.virtualAddress && UInt64(rva) < UInt64($0.virtualAddress) + UInt64(max($0.virtualSize, $0.rawSize)) }
    }

    /// A wrapper TLS callback would still execute before the restored entry
    /// point. Refuse this unimplemented layout instead of dropping live code.
    func tlsReferences(_ bind: Section, in h: FileHandle) throws -> Bool {
        guard dataDirectories.count > 9, dataDirectories[9].rva != 0 else { return false }
        func bytes(_ rva: UInt32, count: Int) throws -> [UInt8] {
            guard let s = section(containingRVA: rva),
                  UInt64(rva) - UInt64(s.virtualAddress) + UInt64(count) <= UInt64(s.rawSize) else {
                throw SteamError.unsupported("TLS data lies outside the PE raw image")
            }
            try h.seek(toOffset: UInt64(s.rawPointer) + UInt64(rva) - UInt64(s.virtualAddress))
            guard let d = try h.read(upToCount: count), d.count == count else {
                throw SteamError.unsupported("truncated PE TLS data")
            }
            return [UInt8](d)
        }
        let tls = try bytes(dataDirectories[9].rva, count: is64 ? 40 : 24)
        let callbacks = is64 ? SteamStub.u64(tls, 24) : UInt64(SteamStub.u32(tls, 12))
        if callbacks == 0 { return false }
        guard callbacks >= imageBase, let rva = UInt32(exactly: callbacks - imageBase) else {
            throw SteamError.unsupported("invalid TLS callback address")
        }
        for i in 0..<1024 {
            let at = UInt64(rva) + UInt64(i * (is64 ? 8 : 4))
            guard let at = UInt32(exactly: at) else { throw SteamError.unsupported("TLS callback table overflow") }
            let raw = try bytes(at, count: is64 ? 8 : 4)
            let callback = is64 ? SteamStub.u64(raw, 0) : UInt64(SteamStub.u32(raw, 0))
            if callback == 0 { return false }
            if callback >= imageBase,
               callback - imageBase >= UInt64(bind.virtualAddress),
               callback - imageBase < UInt64(bind.virtualAddress) + UInt64(max(bind.virtualSize, bind.rawSize)) { return true }
        }
        throw SteamError.unsupported("unterminated TLS callback table")
    }

    static func read(_ h: FileHandle) throws -> PEImage {
        func bytes(_ offset: Int, _ count: Int) throws -> [UInt8] {
            try h.seek(toOffset: UInt64(offset))
            guard let d = try h.read(upToCount: count), d.count == count else { throw SteamError.unsupported("truncated PE") }
            return [UInt8](d)
        }
        let dos = try bytes(0, 0x40)
        guard dos[0] == 0x4d, dos[1] == 0x5a else { throw SteamError.unsupported("not a PE file") }
        let pe = Int(SteamStub.u32(dos, 0x3c))
        let coff = try bytes(pe, 24)
        guard coff[0..<4] == [0x50, 0x45, 0, 0] else { throw SteamError.unsupported("not a PE file") }
        let count = Int(UInt16(coff[6]) | UInt16(coff[7]) << 8)
        let optSize = Int(UInt16(coff[20]) | UInt16(coff[21]) << 8)
        let optAt = pe + 24
        let opt = try bytes(optAt, optSize)
        guard opt.count >= 2 else { throw SteamError.unsupported("truncated optional header") }
        let magic = UInt16(opt[0]) | UInt16(opt[1]) << 8
        guard magic == 0x10b || magic == 0x20b, optSize >= (magic == 0x20b ? 112 : 96) else { throw SteamError.unsupported("unknown optional header") }
        let is64 = magic == 0x20b
        let dirAt = is64 ? 112 : 96
        let dirCount = min(Int(SteamStub.u32(opt, dirAt - 4)), (optSize - dirAt) / 8)
        let dirs = (0..<max(0, dirCount)).map { Directory(rva: SteamStub.u32(opt, dirAt + 8 * $0), size: SteamStub.u32(opt, dirAt + 8 * $0 + 4)) }
        let tableAt = optAt + optSize
        let table = try bytes(tableAt, 40 * count)
        let sections = (0..<count).map { i -> Section in
            let o = 40 * i
            let name = String(decoding: table[o..<o + 8].prefix { $0 != 0 }, as: UTF8.self)
            return Section(name: name, virtualSize: SteamStub.u32(table, o + 8), virtualAddress: SteamStub.u32(table, o + 12),
                           rawSize: SteamStub.u32(table, o + 16), rawPointer: SteamStub.u32(table, o + 20),
                           characteristics: SteamStub.u32(table, o + 36))
        }
        return PEImage(coffHeader: pe + 4, optionalHeader: optAt, sectionTable: tableAt, is64: is64,
                       entryPoint: SteamStub.u32(opt, 16), sectionAlignment: SteamStub.u32(opt, 32),
                       imageBase: is64 ? SteamStub.u64(opt, 24) : UInt64(SteamStub.u32(opt, 28)), sections: sections, dataDirectories: dirs)
    }
}
