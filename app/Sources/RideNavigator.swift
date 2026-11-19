import Foundation
import CoreLocation
import Combine

/// Menghubungkan semua bagian Milestone 1:
/// lokasi (GPS) → rute (Apple Maps) → renderer JPEG → Link A (dash), satu frame dalam-jalan,
/// menunggu ACK (cmd 80) sebelum mengirim frame berikutnya.
final class RideNavigator: NSObject, ObservableObject {
    @Published var status: String = "Mencari dash…"

    private let transport = LinkATransport()
    private let session: LinkASession
    private let renderer = DashRenderer()
    private let location = CLLocationManager()
    private let provider: RouteProvider = AppleMapsRouteProvider()

    private var route: [CLLocationCoordinate2D] = []
    private var position: CLLocationCoordinate2D?
    private var paused = false
    private var ackInFlight = false
    private var frameID: UInt16 = 0
    private var timer: Timer?

    override init() {
        session = LinkASession { [weak self] frame in self?.transport.send(frame) }
        super.init()
        transport.onFrame = { [weak self] frame in self?.handleBike(frame) }
        transport.onState = { [weak self] s in
            DispatchQueue.main.async { self?.status = s }
        }
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.allowsBackgroundLocationUpdates = true
        location.pausesLocationUpdatesAutomatically = false
        location.showsBackgroundLocationIndicator = true
    }

    func start() {
        transport.start()
        location.requestAlwaysAuthorization()
        location.startUpdatingLocation()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    /// Mulai rute ke tujuan (mis. hasil parse tautan Google Maps).
    func navigate(to coord: CLLocationCoordinate2D) {
        guard let from = position else { return }
        provider.route(from: from, to: coord) { [weak self] info in
            guard let self = self, let info = info else { return }
            self.route = info.polyline
            self.session.roadText = info.roadName
        }
    }

    private func handleBike(_ frame: LinkAFrame) {
        switch frame.command {
        case 80:
            ackInFlight = false
        case 55:
            paused = false
            session.onBike(frame: frame)
        case 56:
            paused = true
        default:
            session.onBike(frame: frame)
        }
    }

    /// Render & kirim satu frame bila tidak sedang pause dan tidak ada frame yang menunggu ACK.
    private func tick() {
        guard !paused, !ackInFlight, let pos = position, route.count > 1 else { return }
        guard let jpeg = renderer.render(passed: [], ahead: route, center: pos, speedKmh: 0) else { return }
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