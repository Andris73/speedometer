import CoreLocation
import Foundation

// File scope so these stay nonisolated (nested types would inherit @MainActor,
// which conflicts with the synthesized Decodable witness).
private struct Road {
    let id: Int
    let coords: [CLLocationCoordinate2D]
    let limitMph: Double?
}

private struct OverpassResponse: Decodable {
    struct Element: Decodable {
        struct Point: Decodable {
            let lat: Double
            let lon: Double
        }
        let id: Int
        let tags: [String: String]?
        let geometry: [Point]?
    }
    let elements: [Element]
}

/// Looks up the legal speed limit of the road being driven using the
/// OpenStreetMap Overpass API. Nearby drivable ways are fetched as the user
/// moves and each GPS fix is matched to the nearest way locally.
@MainActor
final class SpeedLimitProvider: ObservableObject {
    /// Speed limit of the matched road in mph; nil when unknown or off-road.
    @Published var speedLimitMph: Double?

    private var roads: [Road] = []
    private var lastMatchedRoadID: Int?
    private var fetchCentre: CLLocation?
    private var fetching = false
    private var lastFetchAttempt: Date?

    // Wide enough that a motorway-speed drive can't outrun the coverage
    // between throttled refetches.
    private let fetchRadius = 600.0
    private let refetchDistance = 250.0
    private let matchThreshold = 35.0
    private let minAttemptInterval: TimeInterval = 15

    func update(location: CLLocation) {
        match(location)
        if shouldFetch(for: location) {
            fetch(around: location)
        }
    }

    private func shouldFetch(for location: CLLocation) -> Bool {
        if fetching { return false }
        if let last = lastFetchAttempt, Date().timeIntervalSince(last) < minAttemptInterval { return false }
        guard let centre = fetchCentre else { return true }
        return location.distance(from: centre) > refetchDistance
    }

    // MARK: - Overpass fetch

    private func fetch(around location: CLLocation) {
        fetching = true
        lastFetchAttempt = Date()
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let query = """
        [out:json][timeout:8];
        way(around:\(Int(fetchRadius)),\(lat),\(lon))["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link|living_street)$"];
        out tags geom 80;
        """

        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("Speedometer/1.3 (com.speedometer.app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        request.httpBody = Data("data=\(encoded)".utf8)

        Task { [weak self] in
            defer { self?.fetching = false }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let parsed = Self.parseRoads(data) else { return }
            self?.roads = parsed
            self?.fetchCentre = location
        }
    }

    // MARK: - Response parsing

    private nonisolated static func parseRoads(_ data: Data) -> [Road]? {
        guard let response = try? JSONDecoder().decode(OverpassResponse.self, from: data) else { return nil }
        return response.elements.compactMap { element in
            guard let geometry = element.geometry, geometry.count >= 2 else { return nil }
            return Road(
                id: element.id,
                coords: geometry.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                limitMph: parseLimit(tags: element.tags ?? [:])
            )
        }
    }

    /// Implicit limits used when the tag holds a country default instead of a number.
    private nonisolated static let implicitLimitsMph: [String: Double] = [
        "gb:nsl_single": 60,
        "gb:nsl_dual": 70,
        "gb:motorway": 70,
        "gb:nsl_restricted": 30,
        "gb:urban": 30,
        "gb:zone20": 20,
        "gb:zone30": 30,
    ]

    private nonisolated static func parseLimit(tags: [String: String]) -> Double? {
        for key in ["maxspeed", "maxspeed:forward", "maxspeed:backward"] {
            if let raw = tags[key], let mph = parseValue(raw) { return mph }
        }
        for key in ["maxspeed:type", "source:maxspeed"] {
            if let raw = tags[key], let mph = implicitLimitsMph[raw.lowercased()] { return mph }
        }
        return nil
    }

    private nonisolated static func parseValue(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if value == "walk" { return 5 }
        if value.hasSuffix("mph") {
            return Double(value.dropLast(3).trimmingCharacters(in: .whitespaces))
        }
        for suffix in ["km/h", "kmh", "kph"] where value.hasSuffix(suffix) {
            return Double(value.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)).map { $0 * 0.621371 }
        }
        if let kmh = Double(value) { return kmh * 0.621371 }
        return implicitLimitsMph[value]
    }

    // MARK: - Road matching

    private func match(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 30, !roads.isEmpty else {
            speedLimitMph = nil
            lastMatchedRoadID = nil
            return
        }
        var best: (road: Road, score: Double)?
        for road in roads {
            guard var score = distance(from: location.coordinate, to: road.coords, course: location.course) else { continue }
            // Hysteresis: prefer the previously matched road so the limit
            // doesn't flap between parallel candidates at junctions.
            if road.id == lastMatchedRoadID { score -= 10 }
            if best == nil || score < best!.score { best = (road, score) }
        }
        if let best, best.score <= matchThreshold {
            lastMatchedRoadID = best.road.id
            speedLimitMph = best.road.limitMph
        } else {
            lastMatchedRoadID = nil
            speedLimitMph = nil
        }
    }

    /// Metres from the fix to the way's polyline, with a penalty when the GPS
    /// course disagrees with the segment bearing (disambiguates parallel roads
    /// and overpasses). Equirectangular projection is fine at this scale.
    private func distance(
        from point: CLLocationCoordinate2D,
        to coords: [CLLocationCoordinate2D],
        course: CLLocationDirection
    ) -> Double? {
        let metresPerDegree = 111_320.0
        let cosLat = cos(point.latitude * .pi / 180)
        func project(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            ((c.longitude - point.longitude) * metresPerDegree * cosLat,
             (c.latitude - point.latitude) * metresPerDegree)
        }

        var best: Double?
        for index in 0..<(coords.count - 1) {
            let a = project(coords[index])
            let b = project(coords[index + 1])
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            var t = 0.0
            if lengthSquared > 0 {
                t = max(0, min(1, (-a.x * dx - a.y * dy) / lengthSquared))
            }
            let px = a.x + t * dx
            let py = a.y + t * dy
            var d = (px * px + py * py).squareRoot()
            if course >= 0, lengthSquared > 0 {
                let bearing = atan2(dx, dy) * 180 / .pi
                var diff = abs(bearing - course).truncatingRemainder(dividingBy: 360)
                if diff > 180 { diff = 360 - diff }
                // Ways are undirected; treat opposite bearings as aligned.
                if diff > 90 { diff = 180 - diff }
                if diff > 45 { d += 15 }
            }
            if best == nil || d < best! { best = d }
        }
        return best
    }
}
