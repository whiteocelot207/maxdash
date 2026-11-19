import Foundation
import ExternalAccessory

/// Transport Link A lewat ExternalAccessory (iPhone). Membuka sesi protokol `com.garmin.navilite.data`,
/// menulis frame keluar, dan mem-parse frame masuk. Detail protokol: docs link-a-dash.md.
final class LinkATransport: NSObject {
    static let protocolString = "com.garmin.navilite.data"

    /// True bila sesi dash terbuka (ada accessory terhubung).
    private(set) var isConnected = false

    private var session: EASession?
    private var inStream: InputStream?
    private var outStream: OutputStream?
    private weak var currentAccessory: EAAccessory?
    private var rxBuffer = Data()
    private var pending = Data()

    /// Dipanggil untuk setiap frame lengkap dari motor.
    var onFrame: ((LinkAFrame) -> Void)?
    /// Dipanggil saat status koneksi berubah (teks Bahasa Indonesia).
    var onState: ((String) -> Void)?

    func start() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(accessoryDidConnect),
            name: .EAAccessoryDidConnect, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(accessoryDidDisconnect),
            name: .EAAccessoryDidDisconnect, object: nil)

        if let acc = EAAccessoryManager.shared().connectedAccessories.first(where: {
            $0.protocolStrings.contains(Self.protocolString)
        }) {
            open(accessory: acc)
        } else {
            onState?("Mencari dash…")
        }
    }

    @objc private func accessoryDidConnect(_ note: Notification) {
        guard let acc = note.userInfo?[EAAccessoryKey] as? EAAccessory else { return }
        if acc.protocolStrings.contains(Self.protocolString) { open(accessory: acc) }
    }

    @objc private func accessoryDidDisconnect(_ note: Notification) {
        guard let acc = note.userInfo?[EAAccessoryKey] as? EAAccessory else { return }
        if acc === currentAccessory {
            close()
            onState?("Dash terputus")
        }
    }

    private func open(accessory: EAAccessory) {
        currentAccessory = accessory
        session = EASession(accessory: accessory, forProtocol: Self.protocolString)
        guard let s = session else { onState?("Gagal membuka sesi dash"); return }
        inStream = s.inputStream
        outStream = s.outputStream
        inStream?.delegate = self
        outStream?.delegate = self
        inStream?.schedule(in: .main, forMode: .common)
        outStream?.schedule(in: .main, forMode: .common)
        inStream?.open()
        outStream?.open()
        rxBuffer.removeAll()
        pending.removeAll()
        isConnected = true
        onState?("Dash terhubung")
    }

    func close() {
        isConnected = false
        inStream?.close()
        inStream?.remove(from: .main, forMode: .common)
        outStream?.close()
        outStream?.remove(from: .main, forMode: .common)
        inStream = nil
        outStream = nil
        session = nil
    }

    func send(_ frame: LinkAFrame) {
        pending.append(frame.encode())
        flush()
    }

    private func flush() {
        guard let out = outStream, out.hasSpaceAvailable, !pending.isEmpty else { return }
        let n: Int = pending.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return out.write(base.assumingMemoryBound(to: UInt8.self), maxLength: raw.count)
        }
        if n > 0 { pending.removeFirst(n) }
    }

    private func handleIncoming() {
        guard let input = inStream else { return }
        var buf = [UInt8](repeating: 0, count: 4096)
        while input.hasBytesAvailable {
            let n = input.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            rxBuffer.append(contentsOf: buf[0..<n])
        }
        for frame in LinkAFrame.extractFrames(from: &rxBuffer) {
            onFrame?(frame)
        }
    }
}

extension LinkATransport: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            handleIncoming()
        case .hasSpaceAvailable:
            flush()
        case .errorOccurred, .endEncountered:
            onState?("Koneksi dash berakhir")
        default:
            break
        }
    }
}