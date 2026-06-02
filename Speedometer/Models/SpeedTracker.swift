import CoreLocation
import Foundation

@MainActor
final class SpeedTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var currentSpeed: Double = 0
    @Published var averageSpeed: Double = 0
    @Published var isTracking: Bool = false

    private var speeds: [Double] = []
    private var totalSpeed: Double = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
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

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            let speed = max(location.speed, 0)
            currentSpeed = speed >= 0 ? speed : 0

            if isTracking {
                totalSpeed += currentSpeed
                speeds.append(currentSpeed)
                if !speeds.isEmpty {
                    averageSpeed = totalSpeed / Double(speeds.count)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .denied {
            Task { @MainActor in
                currentSpeed = -1
            }
        }
    }
}
