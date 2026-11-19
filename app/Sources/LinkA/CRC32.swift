import Foundation

/// CRC-32/MPEG-2: polynomial 0x04C11DB7, MSB-first, init 0xFFFFFFFF, tanpa refleksi, tanpa XOR akhir.
/// Nilai uji untuk ASCII "123456789" = 0x0376E6E7.
enum CRC32MPEG2 {
    static func compute(_ data: Data, initial: UInt32 = 0xFFFF_FFFF) -> UInt32 {
        var crc = initial
        for byte in data {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 {
                crc = (crc & 0x8000_0000) != 0 ? ((crc << 1) ^ 0x04C1_1DB7) : (crc << 1)
            }
        }
        return crc
    }

    /// Format "0x........" (huruf besar, 8 digit) untuk membandingkan dengan vektor.
    static func hex(_ value: UInt32) -> String {
        var s = String(value, radix: 16, uppercase: true)
        if s.count < 8 { s = String(repeating: "0", count: 8 - s.count) + s }
        return "0x" + s
    }
}