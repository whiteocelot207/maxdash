import CoreLocation
import MapKit

/// Hasil rute yang dipakai untuk menggambar frame & mengirim nama jalan ke dash.
struct RouteInfo {
    var polyline: [CLLocationCoordinate2D]
    var distance: Double
    var travelTime: Double
    var roadName: String
}

/// Sumber rute. Default: Apple Maps (gratis, tanpa kunci).
protocol RouteProvider {
    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
               completion: @escaping (RouteInfo?) -> Void)
}

/// Rute via Apple Maps (MKDirections). Cocok untuk skuter di kota.
final class AppleMapsRouteProvider: RouteProvider {
    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
               completion: @escaping (RouteInfo?) -> Void) {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        req.transportType = .automobile
        MKDirections(request: req).calculate { response, _ in
            guard let r = response?.routes.first else { completion(nil); return }
            var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                                  count: r.polyline.pointCount)
            r.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: r.polyline.pointCount))
            completion(RouteInfo(polyline: coords,
                                 distance: r.distance,
                                 travelTime: r.expectedTravelTime,
                                 roadName: r.name))
        }
    }
}