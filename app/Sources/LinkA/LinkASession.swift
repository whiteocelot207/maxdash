import Foundation

/// Mesin sesi Link A: mengurus handshake, init, 55/56, dan reply re-arm handlebar.
/// Sesi mengirim frame lewat closure `send`. Semua frame keluar adalah arah ponsel→dash (0x06).
/// Logika ini harus lulus vektor handshake-nmax-turbo.json.
final class LinkASession {
    typealias Send = (LinkAFrame) -> Void

    private let send: Send

    private(set) var seen83 = false
    private(set) var initSent = false
    private(set) var started = false

    /// Teks road bar saat ini (default satu spasi = kosong). Dikirim ulang tiap 55.
    var roadText: String = " "
    /// Batas kecepatan (km/jam) untuk rambu dash; 0 = tanpa rambu.
    var speedLimit: Float = 0

    private(set) var partNumber: String?
    private(set) var screen: (width: Int, height: Int) = (480, 234)

    init(send: @escaping Send) {
        self.send = send
    }

    private func emit(_ command: UInt8, _ flag: UInt8, _ payload: Data) {
        send(LinkAFrame(command: command, flag: flag, payload: payload))
    }

    /// Proses satu frame dari motor.
    func onBike(frame: LinkAFrame) {
        switch frame.command {
        case 66:
            // Serial: balas hello (81 lalu 33).
            emit(81, 0, Data([0x01, 0x00]))
            emit(33, 1, Data([0x7C, 0x06, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]))
        case 82:
            // 82 setelah 83 memicu init. 82 sebelum 83 diabaikan.
            if seen83 && !initSent {
                sendInit()
                initSent = true
            }
        case 83:
            seen83 = true
            initSent = false
            let b = [UInt8](frame.payload)
            if b.count >= 16 {
                let partBytes = b[0..<12].map { $0 ^ 0x0A }
                let part = String(bytes: partBytes, encoding: .ascii) ?? ""
                partNumber = part
                screen = LinkASession.screenForPart(part)
                let key = Data(b[12..<16].map { $0 ^ 0x0A })
                emit(84, 1, key)
            }
        case 55:
            // Show frames: rider menekan Home / kembali ke peta.
            let b = [UInt8](frame.payload)
            if b.count >= 2 && b[0] == 1 && b[1] == 0 {
                emit(2, 0, Data([0x00, 0x00]))
                emit(14, 1, Data([0x07, 0x1A, 0x00, 0x00]))
                emit(13, 0, Data([0x01, 0x00]))
                emit(3, 1, Data(roadText.utf8))
                emit(10, 0, Data([0x00, 0x00]))
                emit(11, 0, Data([0x00, 0x00]))
                started = true
            }
        case 51, 52:
            // UP / DOWN: wajib kirim re-arm (14 flag 1 kosong) tiap tekan.
            emit(14, 1, Data([0x07, 0x1A, 0x00, 0x00]))
        default:
            break
        }
    }

    private func sendInit() {
        emit(2, 0, Data([0x00, 0x00]))
        emit(31, 0, Data([0x01, 0x00]))
        emit(10, 0, Data([0x00, 0x00]))
        emit(14, 1, Data([0x07, 0x1A, 0x00, 0x00]))
        emit(11, 0, Data([0x00, 0x00]))
        emit(13, 0, Data([0x01, 0x00]))
        emit(3, 1, Data(roadText.utf8))

        // cmd 17: f32 LE limit, u8 panjang, "km/h"
        var limit = Data(count: 9)
        let bits = speedLimit.bitPattern.littleEndian
        limit[0] = UInt8(truncatingIfNeeded: bits)
        limit[1] = UInt8(truncatingIfNeeded: bits >> 8)
        limit[2] = UInt8(truncatingIfNeeded: bits >> 16)
        limit[3] = UInt8(truncatingIfNeeded: bits >> 24)
        limit[4] = 4
        let unit = Array("km/h".utf8)
        for i in 0..<unit.count { limit[5 + i] = unit[i] }
        emit(17, 1, limit)

        emit(12, 0, Data([0x01, 0x00]))
    }

    /// Ukuran layar dari nomor part dash.
    static func screenForPart(_ part: String) -> (width: Int, height: Int) {
        if part == "006-B3952-01" { return (480, 234) }
        if part.contains("006-B4160") { return (480, 240) }
        return (480, 234)
    }

    /// Encode frame peta (cmd 0, flag 1): mode + frame id u16 LE + JPEG.
    static func mapFrame(jpeg: Data, frameID: UInt16, mode: UInt8 = 0x03) -> LinkAFrame {
        var payload = Data(count: 3)
        payload[0] = mode
        payload[1] = UInt8(truncatingIfNeeded: frameID)
        payload[2] = UInt8(truncatingIfNeeded: frameID >> 8)
        payload.append(contentsOf: jpeg)
        return LinkAFrame(command: 0, flag: 1, payload: payload)
    }
}