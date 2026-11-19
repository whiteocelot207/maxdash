import Foundation

enum LinkAError: Error {
    case shortFrame
    case badMagic
    case badLength
    case badCRC
}

/// Satu frame Link A (header 12 byte + CRC 4 byte + payload).
///
/// Offset: 0..<4 magic "nAl@", 4 versi, 5 arah, 6 command, 7..<11 panjang (u32 LE),
/// 11 flag, 12..<16 CRC (u32 LE, CRC-32/MPEG-2 atas 12 byte header + payload), 16..< payload.
struct LinkAFrame {
    static let magic: [UInt8] = [0x6E, 0x41, 0x6C, 0x40] // nAl@
    static let version: UInt8 = 0x01
    static let phoneToDash: UInt8 = 0x06
    static let maxPayload = 1_048_576 // 1 MiB

    var direction: UInt8
    var command: UInt8
    var flag: UInt8
    var payload: Data

    init(direction: UInt8 = LinkAFrame.phoneToDash, command: UInt8, flag: UInt8, payload: Data) {
        self.direction = direction
        self.command = command
        self.flag = flag
        self.payload = payload
    }

    /// Encode frame lengkap (header + CRC + payload).
    func encode() -> Data {
        var head = Data(count: 12)
        head[0] = LinkAFrame.magic[0]
        head[1] = LinkAFrame.magic[1]
        head[2] = LinkAFrame.magic[2]
        head[3] = LinkAFrame.magic[3]
        head[4] = LinkAFrame.version
        head[5] = direction
        head[6] = command
        let len = UInt32(payload.count)
        head[7] = UInt8(len & 0xFF)
        head[8] = UInt8((len >> 8) & 0xFF)
        head[9] = UInt8((len >> 16) & 0xFF)
        head[10] = UInt8((len >> 24) & 0xFF)
        head[11] = flag

        var body = head
        body.append(payload)
        let crc = CRC32MPEG2.compute(body)

        var out = head
        out.append(UInt8(crc & 0xFF))
        out.append(UInt8((crc >> 8) & 0xFF))
        out.append(UInt8((crc >> 16) & 0xFF))
        out.append(UInt8((crc >> 24) & 0xFF))
        out.append(payload)
        return out
    }

    /// Decode satu frame utuh; memeriksa magic, panjang, dan CRC.
    static func decode(_ data: Data) throws -> LinkAFrame {
        guard data.count >= 16 else { throw LinkAError.shortFrame }
        let b = [UInt8](data)
        guard b[0] == magic[0], b[1] == magic[1], b[2] == magic[2], b[3] == magic[3] else {
            throw LinkAError.badMagic
        }
        let direction = b[5]
        let command = b[6]
        let length = Int(UInt32(b[7]) | (UInt32(b[8]) << 8) | (UInt32(b[9]) << 16) | (UInt32(b[10]) << 24))
        guard length >= 0, 16 + length <= b.count else { throw LinkAError.badLength }
        let flag = b[11]
        let payload = data.subdata(in: 16..<(16 + length))

        var body = data.subdata(in: 0..<12)
        body.append(payload)
        let crc = CRC32MPEG2.compute(body)
        let stored = UInt32(b[12]) | (UInt32(b[13]) << 8) | (UInt32(b[14]) << 16) | (UInt32(b[15]) << 24)
        guard crc == stored else { throw LinkAError.badCRC }

        return LinkAFrame(direction: direction, command: command, flag: flag, payload: payload)
    }

    /// Buffer byte yang datang acak; kembalikan semua frame utuh yang bisa diambil.
    /// Memindai magic, membuang byte sebelum magic, dan melewati frame yang panjangnya mustahil.
    static func extractFrames(from buffer: inout Data) -> [LinkAFrame] {
        var frames: [LinkAFrame] = []
        while buffer.count >= 4 {
            guard let idx = findMagic(buffer) else {
                // Tidak ada magic: sisakan maksimal 3 byte terakhir (magic bisa terpotong di batas).
                if buffer.count > 3 { buffer.removeFirst(buffer.count - 3) }
                break
            }
            if idx > 0 { buffer.removeFirst(idx) }
            guard buffer.count >= 16 else { break }
            let b = [UInt8](buffer)
            let length = Int(UInt32(b[7]) | (UInt32(b[8]) << 8) | (UInt32(b[9]) << 16) | (UInt32(b[10]) << 24))
            if length < 0 || length > maxPayload {
                buffer.removeFirst() // panjang mustahil, geser 1 byte
                continue
            }
            guard buffer.count >= 16 + length else { break } // tunggu sisa byte
            let frameData = buffer.subdata(in: 0..<(16 + length))
            buffer.removeSubrange(0..<(16 + length))
            if let f = try? LinkAFrame.decode(frameData) {
                frames.append(f)
            }
            // CRC buruk: frame sudah dibuang, lanjut memindai.
        }
        return frames
    }

    private static func findMagic(_ buffer: Data) -> Int? {
        let n = buffer.count
        let m = magic.count
        guard n >= m else { return nil }
        let bytes = [UInt8](buffer)
        var i = 0
        while i + m <= n {
            var ok = true
            for j in 0..<m {
                if bytes[i + j] != magic[j] { ok = false; break }
            }
            if ok { return i }
            i += 1
        }
        return nil
    }
}