import Foundation

/// A valid RGB PNG of random pixels, stored without compression so its size
/// is predictable (about width × height × 3 bytes) on every platform.
enum NoisyPNG {
    static func make(width: Int, height: Int, seed: UInt64 = 0x9E37_79B9_7F4A_7C15) -> Data {
        let row = 1 + width * 3
        var pixels = [UInt8](repeating: 0, count: row * height)
        var state = seed
        pixels.withUnsafeMutableBufferPointer { buffer in
            for index in buffer.indices where index % row != 0 {
                // xorshift64; filter byte 0 (none) starts each row.
                state ^= state << 13
                state ^= state >> 7
                state ^= state << 17
                buffer[index] = UInt8(truncatingIfNeeded: state)
            }
        }
        var header = [UInt8]()
        header += bigEndian(UInt32(width)) + bigEndian(UInt32(height))
        header += [8, 2, 0, 0, 0]  // 8-bit RGB, deflate, no filter, no interlace
        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        png += chunk("IHDR", header)
        png += chunk("IDAT", stored(pixels))
        png += chunk("IEND", [])
        return Data(png)
    }

    /// A zlib stream of stored (uncompressed) deflate blocks.
    private static func stored(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        out.reserveCapacity(bytes.count + bytes.count / 65_535 * 5 + 16)
        var offset = 0
        repeat {
            let length = min(65_535, bytes.count - offset)
            let last: UInt8 = offset + length == bytes.count ? 1 : 0
            out += [last, UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8((~length >> 8) & 0xFF)]
            out += bytes[offset..<offset + length]
            offset += length
        } while offset < bytes.count
        var a: UInt32 = 1, b: UInt32 = 0
        bytes.withUnsafeBufferPointer { buffer in
            for byte in buffer {
                a = (a + UInt32(byte)) % 65_521
                b = (b + a) % 65_521
            }
        }
        return out + bigEndian(b << 16 | a)
    }

    private static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let body = Array(type.utf8) + data
        return bigEndian(UInt32(data.count)) + body + bigEndian(crc32(body))
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var c = UInt32(value)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        crcTable.withUnsafeBufferPointer { table in
            bytes.withUnsafeBufferPointer { buffer in
                for byte in buffer { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
