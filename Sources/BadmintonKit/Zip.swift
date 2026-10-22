import Foundation
import zlib

/// Minimal ZIP reader/writer, compatible with java.util.zip archives
/// (the Android app's ZipOutputStream/ZipInputStream backup format).
///
/// - write: STORED entries with correct CRC-32/sizes (readable by java.util.zip)
/// - read: central-directory based; supports STORED (0) and DEFLATE (8);
///         tolerates data descriptors (java writes zeroed local sizes + flag bit 3)
public enum ZipError: Error, Equatable {
    case invalidArchive
    case unsupportedMethod(UInt16)
    case crcMismatch
    case inflateFailed
    case io
}

enum Zip {
    struct Entry {
        let name: String
        let data: Data
    }

    private static let localSig: UInt32 = 0x04034b50
    private static let centralSig: UInt32 = 0x02014b50
    private static let eocdSig: UInt32 = 0x06054b50

    // MARK: - Write (STORED)

    static func write(_ entries: [Entry]) -> Data {
        var out = Data()
        var central = Data()
        var offset = 0

        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            let crc = crc32Bytes(entry.data)
            let localOffset = offset

            var local = Data()
            local.appendLE(localSig)
            local.appendLE(UInt16(20)) // version needed
            local.appendLE(UInt16(0)) // flags
            local.appendLE(UInt16(0)) // method = STORED
            local.appendLE(UInt16(0)) // mod time
            local.appendLE(UInt16(0)) // mod date
            local.appendLE(crc)
            local.appendLE(UInt32(entry.data.count)) // compressed
            local.appendLE(UInt32(entry.data.count)) // uncompressed
            local.appendLE(UInt16(nameBytes.count))
            local.appendLE(UInt16(0)) // extra len
            local.append(nameBytes)
            local.append(entry.data)

            out.append(local)
            offset += local.count

            central.appendLE(centralSig)
            central.appendLE(UInt16(20)) // version made by
            central.appendLE(UInt16(20)) // version needed
            central.appendLE(UInt16(0)) // flags
            central.appendLE(UInt16(0)) // method
            central.appendLE(UInt16(0)) // time
            central.appendLE(UInt16(0)) // date
            central.appendLE(crc)
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt16(nameBytes.count))
            central.appendLE(UInt16(0)) // extra
            central.appendLE(UInt16(0)) // comment
            central.appendLE(UInt16(0)) // disk
            central.appendLE(UInt16(0)) // internal attrs
            central.appendLE(UInt32(0)) // external attrs
            central.appendLE(UInt32(localOffset))
            central.append(nameBytes)
        }

        let cdOffset = offset
        out.append(central)
        offset += central.count

        out.appendLE(eocdSig)
        out.appendLE(UInt16(0)) // disk
        out.appendLE(UInt16(0)) // cd disk
        out.appendLE(UInt16(entries.count))
        out.appendLE(UInt16(entries.count))
        out.appendLE(UInt32(central.count))
        out.appendLE(UInt32(cdOffset))
        out.appendLE(UInt16(0)) // comment len
        return out
    }

    // MARK: - Read (central directory)

    static func read(_ data: Data) throws -> [Entry] {
        // Locate EOCD: scan backwards for signature within last 64KB + 22.
        guard data.count >= 22 else { throw ZipError.invalidArchive }
        var eocdIdx: Int?
        let minIdx = max(0, data.count - 65_557)
        var i = data.count - 22
        while i >= minIdx {
            if data.readUInt32(at: i) == eocdSig {
                eocdIdx = i
                break
            }
            i -= 1
        }
        guard let eocd = eocdIdx else { throw ZipError.invalidArchive }

        let count = Int(data.readUInt16(at: eocd + 10))
        let cdSize = Int(data.readUInt32(at: eocd + 12))
        let cdOffset = Int(data.readUInt32(at: eocd + 16))
        guard cdOffset >= 0, cdOffset + cdSize <= data.count else { throw ZipError.invalidArchive }

        var entries: [Entry] = []
        var p = cdOffset
        for _ in 0..<count {
            guard p + 46 <= data.count, data.readUInt32(at: p) == centralSig else { throw ZipError.invalidArchive }
            let method = data.readUInt16(at: p + 10)
            let crc = data.readUInt32(at: p + 16)
            let cSize = Int(data.readUInt32(at: p + 20))
            let uSize = Int(data.readUInt32(at: p + 24))
            let nameLen = Int(data.readUInt16(at: p + 28))
            let extraLen = Int(data.readUInt16(at: p + 30))
            let commentLen = Int(data.readUInt16(at: p + 32))
            let localOffset = Int(data.readUInt32(at: p + 42))
            guard p + 46 + nameLen <= data.count else { throw ZipError.invalidArchive }
            let nameData = data.subdata(in: (p + 46)..<(p + 46 + nameLen))
            guard let name = String(data: nameData, encoding: .utf8) else { throw ZipError.invalidArchive }
            if name.hasSuffix("/") { // directory entry — nothing to extract
                p += 46 + nameLen + extraLen + commentLen
                continue
            }

            // Local header: skip its own name/extra lengths (may differ from central).
            guard localOffset + 30 <= data.count, data.readUInt32(at: localOffset) == localSig else { throw ZipError.invalidArchive }
            let lNameLen = Int(data.readUInt16(at: localOffset + 26))
            let lExtraLen = Int(data.readUInt16(at: localOffset + 28))
            let dataStart = localOffset + 30 + lNameLen + lExtraLen
            guard dataStart + cSize <= data.count else { throw ZipError.invalidArchive }
            let compressed = data.subdata(in: dataStart..<(dataStart + cSize))

            let raw: Data
            switch method {
            case 0:
                raw = compressed
            case 8:
                raw = try inflate(compressed, expectedSize: uSize)
            default:
                throw ZipError.unsupportedMethod(method)
            }
            if crc32Bytes(raw) != crc { throw ZipError.crcMismatch }
            entries.append(Entry(name: name, data: raw))
            p += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }

    // MARK: - zlib helpers

    private static func crc32Bytes(_ data: Data) -> UInt32 {
        var crc: uLong = 0
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            if let base = buf.baseAddress {
                crc = zlib.crc32(crc, base.assumingMemoryBound(to: Bytef.self), uInt(buf.count))
            }
        }
        return UInt32(truncatingIfNeeded: crc)
    }

    private static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        if input.isEmpty { return Data() }
        var stream = z_stream()
        // -15 = raw DEFLATE (what ZIP entries use; no zlib/gzip wrapper)
        var status = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw ZipError.inflateFailed }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunkSize = max(16 * 1024, expectedSize + 1)
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        try input.withUnsafeBytes { (inBuf: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: inBuf.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(inBuf.count)
            while true {
                status = buffer.withUnsafeMutableBytes { outBuf -> Int32 in
                    stream.next_out = outBuf.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(outBuf.count)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
                if status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR {
                    throw ZipError.inflateFailed
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(buffer, count: produced)
                }
                if status == Z_STREAM_END { break }
                if status == Z_BUF_ERROR && produced == 0 { throw ZipError.inflateFailed }
                if stream.avail_in == 0 && produced == 0 && status != Z_STREAM_END { break }
            }
        }
        return output
    }
}

// MARK: - Data little-endian append/read

private extension Data {
    mutating func appendLE(_ v: UInt16) {
        append(contentsOf: [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)])
    }

    mutating func appendLE(_ v: UInt32) {
        append(contentsOf: [
            UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff),
        ])
    }

    func readUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
