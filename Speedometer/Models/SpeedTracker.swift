import CoreLocation
import Foundation

@MainActor
final class SpeedTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var currentSpeed: Double = 0
    @Published var averageSpeed: Double = 0
    @Published var isTracking: Bool = false
    @Published var authorizationDenied = false

    private var speeds: [Double] = []
    private var totalSpeed: Double = 0
    private var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [self] in
            switch status {
            case .denied, .restricted:
                authorizationDenied = true
            case .authorizedWhenInUse, .authorizedAlways:
                authorizationDenied = false
                self.manager.startUpdatingLocation()
            case .notDetermined:
                self.manager.requestWhenInUseAuthorization()
            @unknown default:
                break
            }
        }
    }

    func startTrackingAverage() {
        speeds = []
        totalSpeed = 0
        averageSpeed = 0
        isTracking = true
    }

    func stopTrackingAverage() {
        isTracking = false
    }

    private func computeMph(from location: CLLocation) -> Double {
        if location.speed >= 0 {
            return location.speed * 2.23694
        }
        if let last = lastLocation {
            let distance = location.distance(from: last)
            let time = location.timestamp.timeIntervalSince(last.timestamp)
            if time > 0 {
                return (distance / time) * 2.23694
            }
        }
        return 0
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [self] in
            guard let location = locations.last else { return }
            let mph = computeMph(from: location)
            lastLocation = location
            currentSpeed = mph
            if isTracking {
                totalSpeed += mph
                speeds.append(mph)
                averageSpeed = totalSpeed / Double(speeds.count)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            if clError.code == .denied {
                Task { @MainActor in authorizationDenied = true }
            }
        }
    }
}
