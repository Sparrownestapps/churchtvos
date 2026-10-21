import Foundation
import Compression

/// Why a zip (and so a .pptx) could not be read. `errorDescription` is safe to show to people.
public enum ZipError: Error, LocalizedError, Equatable {
    case notAZip
    case zip64
    case encrypted
    case unsupportedMethod(Int)
    case corrupt(String)
    case tooLarge(String)
    case tooManyEntries

    public var errorDescription: String? {
        switch self {
        case .notAZip: return "This file is not a valid PowerPoint (.pptx) file."
        case .zip64: return "This file is too large or uses a format that is not supported (zip64)."
        case .encrypted: return "This PowerPoint file is password protected. Remove the password in PowerPoint and try again."
        case .unsupportedMethod: return "This PowerPoint file uses a compression method that is not supported."
        case .corrupt: return "This PowerPoint file looks damaged and could not be read."
        case .tooLarge(let n): return "The part \"\(n)\" of this file is too large to import."
        case .tooManyEntries: return "This file has too many parts to import."
        }
    }
}

public struct ZipEntry: Hashable, Sendable {
    public var name: String
    public var method: Int
    public var compressedSize: Int
    public var uncompressedSize: Int
    public var localHeaderOffset: Int
    public var flags: Int
    public var isDirectory: Bool { name.hasSuffix("/") }
}

/// A small read-only zip reader (stored and deflate entries, no zip64, no encryption) built on Foundation and the Compression framework.
/// Used for .pptx files. Every size is checked before memory is allocated, so a hostile file cannot make the app allocate more than
/// `maxEntryBytes` per entry or read more than `maxEntries` entries.
public final class ZipArchive {
    public static let maxEntries = 5_000
    /// Default cap for one entry when the caller gives none.
    public static let defaultMaxEntryBytes = 64 * 1024 * 1024

    private let data: Data
    public let entries: [ZipEntry]
    private let index: [String: ZipEntry]

    public convenience init(url: URL) throws {
        let d: Data
        do { d = try Data(contentsOf: url, options: .mappedIfSafe) } catch { throw ZipError.corrupt("unreadable") }
        try self.init(data: d)
    }

    public init(data: Data) throws {
        self.data = data
        let base = data.startIndex
        let count = data.count
        func u16(_ o: Int) -> Int { Int(data[base + o]) | Int(data[base + o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard count >= 22 else { throw ZipError.notAZip }

        // End of central directory record: last 22 + comment bytes.
        var eocd = -1
        var i = count - 22
        let lowest = max(0, count - 22 - 65_535)
        while i >= lowest {
            if u32(i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let total = u16(eocd + 10)
        let cdSize = u32(eocd + 12)
        let cdOffset = u32(eocd + 16)
        if total == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF { throw ZipError.zip64 }
        guard total <= Self.maxEntries else { throw ZipError.tooManyEntries }
        guard cdOffset >= 0, cdOffset + cdSize <= count else { throw ZipError.corrupt("central directory") }

        var list: [ZipEntry] = []
        var p = cdOffset
        for _ in 0..<total {
            guard p + 46 <= count, u32(p) == 0x0201_4b50 else { throw ZipError.corrupt("central directory entry") }
            let flags = u16(p + 8)
            let method = u16(p + 10)
            let csize = u32(p + 20)
            let usize = u32(p + 24)
            let nameLen = u16(p + 28)
            let extraLen = u16(p + 30)
            let commentLen = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + nameLen <= count else { throw ZipError.corrupt("entry name") }
            if csize == 0xFFFF_FFFF || usize == 0xFFFF_FFFF || local == 0xFFFF_FFFF { throw ZipError.zip64 }
            let nameData = data.subdata(in: (base + p + 46)..<(base + p + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            list.append(ZipEntry(name: name, method: method, compressedSize: csize, uncompressedSize: usize, localHeaderOffset: local, flags: flags))
            p += 46 + nameLen + extraLen + commentLen
        }
        entries = list
        var map: [String: ZipEntry] = [:]
        for e in list { map[e.name] = e }
        index = map
    }

    public func entry(named name: String) -> ZipEntry? { index[name] ?? index[name.lowercased()] }

    /// The uncompressed bytes of an entry, or nil when there is no such entry. Throws for damaged, encrypted or oversized entries.
    public func data(named name: String, maxBytes: Int = ZipArchive.defaultMaxEntryBytes) throws -> Data? {
        guard let e = entry(named: name) else { return nil }
        return try data(for: e, maxBytes: maxBytes)
    }

    public func data(for e: ZipEntry, maxBytes: Int = ZipArchive.defaultMaxEntryBytes) throws -> Data {
        if e.flags & 0x1 != 0 { throw ZipError.encrypted }
        guard e.uncompressedSize <= maxBytes else { throw ZipError.tooLarge(e.name) }
        let base = data.startIndex
        let count = data.count
        func u16(_ o: Int) -> Int { Int(data[base + o]) | Int(data[base + o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        let h = e.localHeaderOffset
        guard h >= 0, h + 30 <= count, u32(h) == 0x0403_4b50 else { throw ZipError.corrupt(e.name) }
        let start = h + 30 + u16(h + 26) + u16(h + 28)
        guard start >= 0, start + e.compressedSize <= count else { throw ZipError.corrupt(e.name) }
        let raw = data.subdata(in: (base + start)..<(base + start + e.compressedSize))
        switch e.method {
        case 0:
            guard raw.count == e.uncompressedSize else { throw ZipError.corrupt(e.name) }
            return raw
        case 8:
            if e.uncompressedSize == 0 { return Data() }
            var out = Data(count: e.uncompressedSize)
            let written: Int = out.withUnsafeMutableBytes { dst in
                raw.withUnsafeBytes { src in
                    guard let d = dst.bindMemory(to: UInt8.self).baseAddress, let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    // COMPRESSION_ZLIB is raw deflate, which is what zip stores.
                    return compression_decode_buffer(d, e.uncompressedSize, s, raw.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard written == e.uncompressedSize else { throw ZipError.corrupt(e.name) }
            return out
        default:
            throw ZipError.unsupportedMethod(e.method)
        }
    }
}

/// Writes a store-only zip (no compression). Used for test files and the debug sample, never for user data.
public enum ZipWriter {
    public static func make(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        func le16(_ v: Int) -> Data { Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff)]) }
        func le32(_ v: Int) -> Data { le16(v & 0xffff) + le16((v >> 16) & 0xffff) }
        for f in files {
            let name = Data(f.name.utf8)
            let crc = crc32(f.data)
            let offset = out.count
            out += le32(0x0403_4b50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0x21) + le32(crc) + le32(f.data.count) + le32(f.data.count)
            out += le16(name.count) + le16(0) + name + f.data
            central += le32(0x0201_4b50) + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0x21) + le32(crc) + le32(f.data.count) + le32(f.data.count)
            central += le16(name.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + name
        }
        let cdOffset = out.count
        out += central
        out += le32(0x0605_4b50) + le16(0) + le16(0) + le16(files.count) + le16(files.count) + le32(central.count) + le32(cdOffset) + le16(0)
        return out
    }

    static func crc32(_ data: Data) -> Int {
        var table = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            table[n] = c
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for b in data { crc = table[Int((crc ^ UInt32(b)) & 0xff)] ^ (crc >> 8) }
        return Int(crc ^ 0xFFFF_FFFF)
    }
}
