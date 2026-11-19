import Foundation
import UIKit
import CoreLocation
import MapKit
import Combine
import AVFoundation

/// Menghubungkan semua bagian Milestone 1:
/// lokasi (GPS) → rute (Apple Maps) → renderer JPEG → Link A (dash), satu frame dalam-jalan,
/// menunggu ACK (cmd 80) sebelum mengirim frame berikutnya.
final class RideNavigator: NSObject, ObservableObject {
    @Published var status: String = "Mencari dash…"

    /// Batas kecepatan default yang ditampilkan di rambu dash (bisa diubah di Setting).
    var defaultSpeedLimit: Float = 60
    /// Persentase bensin (untuk panel data & speedometer).
    var fuelLevelPercent: Double = 62
    /// Tampilan dash aktif (diganti klik 2x stang).
    @Published var currentView: DashView = .map
    /// Slot data yang ditampilkan di panel kanan (4 kartu kecil).
    @Published var selectedSlots: [DataSlot] = DataSlot.defaults
    /// Frame terakhir yang dirender (untuk preview realtime di Home).
    @Published var previewImage: UIImage?
    /// Status GPS (untuk chip di Home).
    @Published var gpsActive = false
    /// Status koneksi dash (untuk chip di Home).
    @Published var dashConnected = false
    /// GPS diaktifkan pengguna.
    @Published var gpsEnabled = true

    private let music = MusicController()
    private var lastPress: Date?
    private var simulating = false
    private var simRoute: [CLLocationCoordinate2D] = []
    private var simIndex = 0
    private var phoneBattery: Double = 0
    private var phoneVolume: Double = 0
    private var odo: Double = 28181
    private var coolant: Double? = nil
    private var voltage: Double? = nil
    private let transport = LinkATransport()
    private var session: LinkASession!
    private let renderer = DashRenderer()
    private let location = CLLocationManager()
    private let provider: RouteProvider = AppleMapsRouteProvider()

    private var route: [CLLocationCoordinate2D] = []
    private var position: CLLocationCoordinate2D?
    private var bikeSpeedKmh: Int = 0
    private var paused = false
    private var ackInFlight = false
    private var frameID: UInt16 = 0
    private var timer: Timer?

    override init() {
        super.init()
        session = LinkASession { [weak self] frame in
            guard let self = self else { return }
            self.transport.send(frame)
        }
        transport.onFrame = { [weak self] frame in
            guard let self = self else { return }
            self.handleBike(frame)
        }
        transport.onState = { [weak self] s in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.status = s
                self.dashConnected = self.transport.isConnected
            }
        }
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.allowsBackgroundLocationUpdates = true
        location.pausesLocationUpdatesAutomatically = false
        location.showsBackgroundLocationIndicator = true
    }

    func start() {
        // Saat berjalan sebagai test host (XCTest), jangan aktifkan lokasi/EA/timer.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        session.speedLimit = defaultSpeedLimit
        transport.start()
        let gpsOn = UserDefaults.standard.object(forKey: "gpsEnabled") as? Bool ?? true
        gpsEnabled = gpsOn
        if gpsOn {
            location.requestAlwaysAuthorization()
            location.startUpdatingLocation()
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    /// Aktif/nonaktifkan GPS (dari Setting).
    func setGPS(_ enabled: Bool) {
        gpsEnabled = enabled
        if enabled {
            location.requestAlwaysAuthorization()
            location.startUpdatingLocation()
        } else {
            location.stopUpdatingLocation()
            gpsActive = false
        }
    }

    /// Mode simulasi: buat rute contoh & gerakkan posisi sepanjang rute (untuk uji tanpa berkendara).
    func startSimulation() {
        let base = position ?? CLLocationCoordinate2D(latitude: -6.2088, longitude: 106.8456)
        var pts: [CLLocationCoordinate2D] = []
        for i in 0..<80 {
            let dLat = Double(i) * 0.0004
            let dLng = sin(Double(i) / 12) * 0.0004
            pts.append(CLLocationCoordinate2D(latitude: base.latitude + dLat, longitude: base.longitude + dLng))
        }
        simRoute = pts
        simIndex = 0
        simulating = true
        route = pts
        position = pts[0]
        session.beginStreaming()
        session.roadText = "Simulasi"
        paused = false
        ackInFlight = false
        status = "Simulasi aktif"
    }

    /// Baca pasteboard (diisi share extension / salin manual) lalu mulai rute.
    func navigateFromPasteboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            DispatchQueue.main.async { self.status = "Pasteboard kosong" }
            return
        }
        let result = ShareLink.parse(text)
        if case .redirect(let urlStr) = result {
            ShareLink.resolveRedirect(urlStr) { [weak self] resolved in
                guard let self = self, let resolved = resolved else { return }
                self.navigate(to: ShareLink.parse(resolved))
            }
        } else {
            navigate(to: result)
        }
    }

    /// Mulai rute ke tujuan (mis. hasil parse tautan Google Maps).
    func navigate(to result: ShareResult) {
        switch result {
        case .coords(let lat, let lng, _):
            startRoute(to: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        case .directions(let dest, _):
            if let lat = dest.lat, let lng = dest.lng {
                startRoute(to: CLLocationCoordinate2D(latitude: lat, longitude: lng))
            } else if let q = dest.q {
                geocode(q) { [weak self] c in if let c = c { self?.startRoute(to: c) } }
            }
        case .query(let q):
            geocode(q) { [weak self] c in if let c = c { self?.startRoute(to: c) } }
        default:
            break
        }
    }

    /// Cari tujuan dari teks (mis. nama kota) lalu mulai rute.
    func navigate(toText q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        geocode(trimmed) { [weak self] c in
            guard let self = self else { return }
            if let c = c {
                self.startRoute(to: c)
            } else {
                DispatchQueue.main.async { self.status = "Tujuan tidak ditemukan" }
            }
        }
    }

    private func startRoute(to coord: CLLocationCoordinate2D) {
        guard let from = position else {
            DispatchQueue.main.async { self.status = "Menunggu GPS…" }
            return
        }
        provider.route(from: from, to: coord) { [weak self] info in
            guard let self = self, let info = info else { return }
            DispatchQueue.main.async {
                self.route = info.polyline
                self.session.roadText = info.roadName
                self.status = "Navigasi dimulai"
            }
        }
    }

    /// Cari koordinat dari teks nama tempat (mis. hasil share tanpa koordinat).
    private func geocode(_ q: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        MKLocalSearch(request: request).start { response, _ in
            DispatchQueue.main.async {
                completion(response?.mapItems.first?.placemark.coordinate)
            }
        }
    }

    private func handleBike(_ frame: LinkAFrame) {
        switch frame.command {
        case 80:
            ackInFlight = false
        case 65:
            let b = [UInt8](frame.payload)
            if b.count >= 3 { bikeSpeedKmh = Int(b[1]) | (Int(b[2]) << 8) }
            session.onBike(frame: frame)
        case 51, 52:
            handleBarPress()
            session.onBike(frame: frame) // re-arm (14)
        case 55:
            paused = false
            session.onBike(frame: frame)
        case 56:
            paused = true
        default:
            session.onBike(frame: frame)
        }
    }

    /// Klik 2x stang (dua tekanan < 0.4 s) → pindah tampilan dash.
    private func handleBarPress() {
        let now = Date()
        if let last = lastPress, now.timeIntervalSince(last) < 0.4 {
            cycleView()
            lastPress = nil
        } else {
            lastPress = now
        }
    }

    private func cycleView() {
        let all = DashView.allCases
        if let i = all.firstIndex(of: currentView) {
            currentView = all[(i + 1) % all.count]
        }
    }

    /// Render frame (preview realtime + kirim ke dash bila terhubung & sesi siap).
    private func tick() {
        // Simulasi: gerakkan posisi sepanjang rute.
        if simulating, simIndex < simRoute.count - 1 {
            simIndex += 1
            position = simRoute[simIndex]
        }
        guard let pos = position, route.count > 1 else { return }

        // Data HP (baterai & volume) + panel data yang dipilih.
        phoneBattery = Double(max(0, UIDevice.current.batteryLevel) * 100)
        phoneVolume = Double(AVAudioSession.shared().outputVolume * 100)
        let fuel = FuelCalculator(tankLiters: 13.2, levelPercent: fuelLevelPercent, consumption: 22)
        let readouts = selectedSlots.map {
            DataSlotReader.read($0, fuel: fuel, speedKmh: bikeSpeedKmh, battery: phoneBattery,
                                volume: phoneVolume, coolant: coolant, voltage: voltage, odo: odo)
        }
        let slots = readouts.map { ($0.label, $0.value) }

        guard let jpeg = renderer.render(view: currentView,
                                         speedKmh: bikeSpeedKmh,
                                         limitKmh: Int(session.speedLimit),
                                         fuelPercent: fuelLevelPercent,
                                         slots: slots,
                                         route: route,
                                         center: pos,
                                         music: music.nowPlaying) else { return }

        // Preview realtime di Home.
        if let img = UIImage(data: jpeg) { previewImage = img }

        // Streaming ke dash: hanya bila terhubung, sesi siap (Home ditekan / simulasi), tidak pause, tidak menunggu ACK.
        guard transport.isConnected, session.started, !paused, !ackInFlight else { return }
        frameID &+= 1
        if frameID == 0 { frameID = 1 }
        let frame = LinkASession.mapFrame(jpeg: jpeg, frameID: frameID, mode: 0x03)
        ackInFlight = true
        transport.send(frame)
    }
}

extension RideNavigator: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let last = locations.last {
            position = last.coordinate
            if !gpsActive { gpsActive = true }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        gpsActive = false
        DispatchQueue.main.async { self.status = "GPS: \(error.localizedDescription)" }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            location.startUpdatingLocation()
        default:
            break
        }
    }
}