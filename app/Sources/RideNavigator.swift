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

    private let music = MusicController()
    private var lastPress: Date?
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
            DispatchQueue.main.async { self.status = s }
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
        location.requestAlwaysAuthorization()
        location.startUpdatingLocation()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
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

    /// Render & kirim satu frame bila tidak sedang pause dan tidak ada frame yang menunggu ACK.
    private func tick() {
        guard session.started, !paused, !ackInFlight, let pos = position, route.count > 1 else { return }

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
        frameID &+= 1
        if frameID == 0 { frameID = 1 }
        let frame = LinkASession.mapFrame(jpeg: jpeg, frameID: frameID, mode: 0x03)
        ackInFlight = true
        transport.send(frame)
    }
}

extension RideNavigator: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let last = locations.last { position = last.coordinate }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
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