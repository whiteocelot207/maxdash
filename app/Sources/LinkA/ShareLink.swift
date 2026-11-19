import Foundation

/// Tempat hasil parse tautan (berisi koordinat ATAU teks untuk dicari).
struct SharePlace {
    var lat: Double?
    var lng: Double?
    var name: String?
    var q: String?
}

/// Hasil parse teks yang dibagikan dari Google/Apple Maps.
enum ShareResult {
    case coords(lat: Double, lng: Double, name: String?)
    case query(String)
    case directions(destination: SharePlace, stops: [SharePlace])
    case redirect(String)
    case none
}

private struct Waypoint {
    var name: String?
    var lat: Double?
    var lng: Double?
}

/// Parser tautan Google/Apple Maps. Harus lulus share-links.json.
/// Aturan: docs/how-it-works/routing-options.md
enum ShareLink {

    static func parse(_ text: String) -> ShareResult {
        guard let urlStr = firstURL(in: text) else { return .none }
        guard let comps = URLComponents(string: urlStr), let host = comps.host?.lowercased() else { return .none }

        let isGoogle = host.contains("google") || host == "goo.gl" || host.hasSuffix(".goo.gl")
        let isApple = host.contains("apple")
        let isShort = host == "maps.app.goo.gl" || (host == "goo.gl" && comps.path.hasPrefix("/maps"))
        if !isGoogle && !isApple { return .none }
        if isShort { return .redirect(urlStr) }

        let path = comps.path

        if path.contains("/maps/dir/") {
            return parseDirections(urlStr: urlStr, path: path)
        }
        if path.contains("/maps/place/") {
            return parsePlace(urlStr: urlStr, path: path)
        }
        let isApiSearch = comps.queryItems?.contains { $0.name == "api" && $0.value == "1" } ?? false
        if path.contains("/maps/search/") || isApiSearch {
            if let q = queryValue(comps, "query") ?? queryValue(comps, "q") {
                if let c = parseLatLng(q) {
                    return inRange(c.lat, c.lng) ? .coords(lat: c.lat, lng: c.lng, name: nil) : .none
                }
                return .query(q)
            }
        }
        if isApple {
            if let ll = queryValue(comps, "ll"), let c = parseLatLng(ll), inRange(c.lat, c.lng) {
                return .coords(lat: c.lat, lng: c.lng, name: queryValue(comps, "q"))
            }
        }
        for key in ["q", "ll", "query", "destination"] {
            if let val = queryValue(comps, key) {
                if let c = parseLatLng(val) {
                    return inRange(c.lat, c.lng) ? .coords(lat: c.lat, lng: c.lng, name: nil) : .none
                }
                if key == "q" || key == "query" || key == "destination" { return .query(val) }
            }
        }
        if let c = viewportCoord(urlStr) {
            return inRange(c.lat, c.lng) ? .coords(lat: c.lat, lng: c.lng, name: nil) : .none
        }
        return .none
    }

    // MARK: - Directions

    private static func parseDirections(urlStr: String, path: String) -> ShareResult {
        let segs = path.split(separator: "/").map(String.init)
        guard let di = segs.firstIndex(of: "dir") else { return .none }

        var wpSegs: [String] = []
        var i = di + 1
        while i < segs.count {
            let s = segs[i]
            if s.hasPrefix("@") || s.hasPrefix("data=") || s.contains("data=") { break }
            wpSegs.append(s)
            i += 1
        }
        if wpSegs.isEmpty { return .none }

        var coords: [(lat: Double, lng: Double)] = []
        for m in regexGroups("!1d(-?\\d+(?:\\.\\d+)?)!2d(-?\\d+(?:\\.\\d+)?)", urlStr) {
            if m.count >= 3, let lng = Double(m[1]), let lat = Double(m[2]) {
                coords.append((lat, lng))
            }
        }

        var wps: [Waypoint] = []
        for idx in wpSegs.indices {
            let raw = decodeSeg(wpSegs[idx])
            if let pl = parseLatLng(raw) {
                wps.append(Waypoint(name: nil, lat: pl.lat, lng: pl.lng))
            } else if idx < coords.count {
                wps.append(Waypoint(name: raw, lat: coords[idx].lat, lng: coords[idx].lng))
            } else {
                wps.append(Waypoint(name: raw, lat: nil, lng: nil))
            }
        }

        let dest = wps.last!
        var destination: SharePlace
        if let dlat = dest.lat, let dlng = dest.lng, inRange(dlat, dlng) {
            destination = SharePlace(lat: dlat, lng: dlng, name: dest.name, q: nil)
        } else {
            destination = SharePlace(lat: nil, lng: nil, name: nil, q: dest.name)
        }
        if destination.q == nil && destination.lat == nil { return .none }
        if let dlat = destination.lat, let dlng = destination.lng, !inRange(dlat, dlng) { return .none }

        var stops: [SharePlace] = []
        if wps.count > 2 {
            for k in 1..<(wps.count - 1) {
                let w = wps[k]
                if let wlat = w.lat, let wlng = w.lng, inRange(wlat, wlng) {
                    stops.append(SharePlace(lat: wlat, lng: wlng, name: w.name, q: nil))
                }
            }
        }
        return .directions(destination: destination, stops: stops)
    }

    // MARK: - Place

    private static func parsePlace(urlStr: String, path: String) -> ShareResult {
        let segs = path.split(separator: "/").map(String.init)
        guard let pi = segs.firstIndex(of: "place"), pi + 1 < segs.count else { return .none }
        let name = decodeSeg(segs[pi + 1])

        if let m = regexGroups("!3d(-?\\d+(?:\\.\\d+)?)!4d(-?\\d+(?:\\.\\d+)?)", urlStr).first,
           m.count >= 3, let lat = Double(m[1]), let lng = Double(m[2]) {
            if !inRange(lat, lng) { return .none }
            return .coords(lat: lat, lng: lng, name: name.isEmpty ? nil : name)
        }
        return .query(name)
    }

    // MARK: - Helpers

    static func firstURL(in text: String) -> String? {
        regexGroups("https?://[^\\s]+", text).first?.first
    }

    static func decodeSeg(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
    }

    static func parseLatLng(_ s: String) -> (lat: Double, lng: Double)? {
        guard let m = regexGroups("^\\s*(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)\\s*$", s).first,
              m.count >= 3, let lat = Double(m[1]), let lng = Double(m[2]) else { return nil }
        return (lat, lng)
    }

    static func inRange(_ lat: Double, _ lng: Double) -> Bool {
        lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
    }

    private static func viewportCoord(_ urlStr: String) -> (lat: Double, lng: Double)? {
        guard let m = regexGroups("@(-?\\d+(?:\\.\\d+)?),(-?\\d+(?:\\.\\d+)?)(?:,|-?\\d)", urlStr).first,
              m.count >= 3, let lat = Double(m[1]), let lng = Double(m[2]) else { return nil }
        return (lat, lng)
    }

    private static func queryValue(_ comps: URLComponents, _ name: String) -> String? {
        guard let v = comps.queryItems?.first(where: { $0.name == name })?.value else { return nil }
        // URLComponents tidak mengubah '+' menjadi spasi (Node/URLSearchParams melakukannya).
        return v.replacingOccurrences(of: "+", with: " ")
    }

    /// Ikuti redirect tautan pendek (mis. maps.app.goo.gl) dan kembalikan URL tujuan (Location).
    /// Tidak mengikuti redirect lebih dari satu; hanya membaca header Location.
    static func resolveRedirect(_ urlStr: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: urlStr) else { completion(nil); return }
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumRedirects = 0
        let session = URLSession(configuration: config)
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { _, response, _ in
            let loc = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location")
            DispatchQueue.main.async { completion(loc) }
        }.resume()
    }

    private static func regexGroups(_ pattern: String, _ s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        return re.matches(in: s, options: [], range: full).map { m in
            (0..<m.numberOfRanges).map { r -> String in
                let rg = m.range(at: r)
                return rg.location == NSNotFound ? "" : ns.substring(with: rg)
            }
        }
    }
}