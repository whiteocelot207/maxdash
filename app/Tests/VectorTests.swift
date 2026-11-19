import XCTest
import CoreFoundation
@testable import Maxdash

/// Menjalankan kode Link A & parser tautan terhadap SETIAP vektor di folder Tests.
/// Semua harus lulus sebelum dipakai di motor. Vektor = byte asli dari dash asli.
final class VectorTests: XCTestCase {

    // MARK: - Muat vektor

    private func loadJSON(_ name: String) -> [String: Any] {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            XCTFail("vektor tidak ditemukan: \(name).json")
            return [:]
        }
        let data = try! Data(contentsOf: url)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func vectors(_ name: String) -> [[String: Any]] {
        loadJSON(name)["vectors"] as? [[String: Any]] ?? []
    }

    // MARK: - Util

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func data(fromHex s: String) -> Data {
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let chars = s.unicodeScalars.filter { allowed.contains($0) }.map { String($0) }
        var bytes: [UInt8] = []
        var i = 0
        while i + 1 < chars.count {
            if let b = UInt8(chars[i] + chars[i + 1], radix: 16) { bytes.append(b) }
            i += 2
        }
        return Data(bytes)
    }

    private func num(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
    private func int(_ any: Any?) -> Int? { (any as? NSNumber)?.intValue }
    private func str(_ any: Any?) -> String? { any as? String }

    // MARK: - 1) CRC-32/MPEG-2

    func testCRC() {
        for v in vectors("crc") {
            let id = str(v["id"]) ?? "?"
            let input = v["input"] as? [String: Any] ?? [:]
            let expect = v["expect"] as? [String: Any] ?? [:]
            let got = CRC32MPEG2.hex(CRC32MPEG2.compute(data(fromHex: str(input["hex"]) ?? "")))
            XCTAssertEqual(got, str(expect["crc32_mpeg2"]) ?? "", "crc \(id)")
        }
    }

    // MARK: - 2) Encode frame ponsel→dash

    func testFrames() {
        for v in vectors("frames") {
            let id = str(v["id"]) ?? "?"
            let input = v["input"] as? [String: Any] ?? [:]
            let expect = v["expect"] as? [String: Any] ?? [:]
            let frame = LinkAFrame(
                direction: UInt8(int(input["direction"]) ?? 6),
                command: UInt8(int(input["command"]) ?? 0),
                flag: UInt8(int(input["flag"]) ?? 0),
                payload: data(fromHex: str(input["payload_hex"]) ?? ""))
            XCTAssertEqual(hex(frame.encode()), str(expect["frame_hex"]) ?? "", "frame \(id)")
        }
    }

    // MARK: - 3) Decode frame motor→ponsel + makna

    func testCommands() {
        for v in vectors("link-a-commands") {
            let id = str(v["id"]) ?? "?"
            let input = v["input"] as? [String: Any] ?? [:]
            let expect = v["expect"] as? [String: Any] ?? [:]
            let frame = try! LinkAFrame.decode(data(fromHex: str(input["frame_hex"]) ?? ""))

            XCTAssertEqual(Int(frame.command), int(expect["command"]) ?? -1, "cmd \(id)")
            XCTAssertEqual(Int(frame.flag), int(expect["flag"]) ?? -1, "flag \(id)")
            XCTAssertEqual(hex(frame.payload), str(expect["payload_hex"]) ?? "", "payload \(id)")

            let means = Self.interpret(frame)
            if let exp = expect["means"] as? [String: Any] {
                for (key, value) in exp {
                    let got = means[key]
                    if key == "screen" {
                        let want = (value as? [Any])?.compactMap { int($0) } ?? []
                        let gotArr = (got as? [Int]) ?? []
                        XCTAssertEqual(gotArr, want, "means.screen \(id)")
                    } else if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() {
                        let wantBool = value as? Bool ?? false
                        XCTAssertEqual(got as? Bool, wantBool, "means.\(key) \(id)")
                    } else if let wantStr = value as? String {
                        XCTAssertEqual(got as? String, wantStr, "means.\(key) \(id)")
                    } else if let wantInt = int(value) {
                        XCTAssertEqual((got as? NSNumber)?.intValue ?? -1, wantInt, "means.\(key) \(id)")
                    }
                }
            }
        }
    }

    static func interpret(_ frame: LinkAFrame) -> [String: Any] {
        switch frame.command {
        case 66:
            return ["serial": String(decoding: frame.payload, as: UTF8.self)]
        case 82:
            return ["authenticated": frame.payload.first == 1]
        case 83:
            let b = [UInt8](frame.payload)
            guard b.count >= 16 else { return [:] }
            let part = String(bytes: b[0..<12].map { $0 ^ 0x0A }, encoding: .ascii) ?? ""
            let key = b[12..<16].map { $0 ^ 0x0A }
            let keyHex = key.map { String(format: "%02X", $0) }.joined(separator: " ")
            let screen = LinkASession.screenForPart(part)
            return ["part_number": part, "key_hex": keyHex, "screen": [screen.width, screen.height]]
        case 55:
            let b = [UInt8](frame.payload)
            return ["start_frames": b.count >= 2 && b[0] == 1 && b[1] == 0]
        case 56:
            return ["pause": true]
        case 65:
            let b = [UInt8](frame.payload)
            let speed = b.count >= 3 ? Int(b[1]) | (Int(b[2]) << 8) : 0
            return ["speed_kmh": speed]
        case 51:
            return ["button": "up"]
        case 52:
            return ["button": "down"]
        case 80:
            let b = [UInt8](frame.payload)
            let ack = b.count >= 2 ? Int(b[0]) | (Int(b[1]) << 8) : 0
            return ["ack_frame_id": ack]
        default:
            return [:]
        }
    }

    // MARK: - 4) Handshake (sesi)

    func testHandshake() {
        let vec = vectors("handshake-nmax-turbo")[0]
        let steps = (vec["input"] as? [String: Any])?["steps"] as? [[String: Any]] ?? []

        var emitted: [[String: Any]] = []
        let session = LinkASession { frame in
            emitted.append([
                "command": Int(frame.command),
                "flag": Int(frame.flag),
                "payload_hex": hex(frame.payload)
            ])
        }

        for step in steps {
            if str(step["from"]) == "bike" {
                let frame = try! LinkAFrame.decode(data(fromHex: str(step["frame_hex"]) ?? ""))
                session.onBike(frame: frame)
            } else if let must = step["must_send"] as? [[String: Any]] {
                let got = emitted
                emitted.removeAll()
                XCTAssertEqual(got.count, must.count, "jumlah frame (harus \(must.count))")
                for (g, w) in zip(got, must) {
                    XCTAssertEqual(int(g["command"]) ?? -1, int(w["command"]) ?? -1)
                    XCTAssertEqual(int(g["flag"]) ?? -1, int(w["flag"]) ?? -1)
                    XCTAssertEqual(str(g["payload_hex"]) ?? "", str(w["payload_hex"]) ?? "")
                }
            }
        }
    }

    // MARK: - 5) Parser tautan Google Maps

    func testShareLinks() {
        for v in vectors("share-links") {
            let id = str(v["id"]) ?? "?"
            let input = v["input"] as? [String: Any] ?? [:]
            let expect = v["expect"] as? [String: Any] ?? [:]
            let result = ShareLink.parse(str(input["text"]) ?? "")
            let kind = str(expect["kind"]) ?? ""

            switch (kind, result) {
            case ("coords", .coords(let lat, let lng, let name)):
                XCTAssertEqual(lat, num(expect["lat"]) ?? .nan, accuracy: 1e-6, "share \(id) lat")
                XCTAssertEqual(lng, num(expect["lng"]) ?? .nan, accuracy: 1e-6, "share \(id) lng")
                if let en = str(expect["name"]) { XCTAssertEqual(name, en, "share \(id) name") }
            case ("query", .query(let q)):
                XCTAssertEqual(q, str(expect["q"]) ?? "", "share \(id) q")
            case ("redirect", .redirect):
                break
            case ("none", .none):
                break
            case ("directions", .directions(let dest, let stops)):
                let ed = expect["destination"] as? [String: Any] ?? [:]
                if let eq = str(ed["q"]) {
                    XCTAssertEqual(dest.q ?? "", eq, "share \(id) dest.q")
                } else {
                    XCTAssertEqual(dest.lat ?? .nan, num(ed["lat"]) ?? .nan, accuracy: 1e-6, "share \(id) dest.lat")
                    XCTAssertEqual(dest.lng ?? .nan, num(ed["lng"]) ?? .nan, accuracy: 1e-6, "share \(id) dest.lng")
                    if let en = str(ed["name"]) { XCTAssertEqual(dest.name, en, "share \(id) dest.name") }
                }
                let es = expect["stops"] as? [[String: Any]] ?? []
                XCTAssertEqual(stops.count, es.count, "share \(id) stops count")
                for (gs, esx) in zip(stops, es) {
                    XCTAssertEqual(gs.lat ?? .nan, num(esx["lat"]) ?? .nan, accuracy: 1e-6, "share \(id) stop.lat")
                    XCTAssertEqual(gs.lng ?? .nan, num(esx["lng"]) ?? .nan, accuracy: 1e-6, "share \(id) stop.lng")
                    if let en = str(esx["name"]) { XCTAssertEqual(gs.name, en, "share \(id) stop.name") }
                }
            default:
                XCTFail("share \(id): kind \(kind) vs \(result)")
            }
        }
    }
}