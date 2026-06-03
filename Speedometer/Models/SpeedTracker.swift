import CoreLocation
import Foundation

@MainActor
final class SpeedTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum TrackingState { case idle, paused, tracking }
    enum GPSStatus { case searching, locked, error }

    private let manager = CLLocationManager()

    @Published var currentSpeed: Double = 0
    @Published var averageSpeed: Double = 0
    @Published var trackingState: TrackingState = .idle
    @Published var gpsStatus: GPSStatus = .searching
    @Published var authorizationDenied = false
    @Published var totalTripDistance: Double = 0
    @Published var sessionDistance: Double = 0

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
                gpsStatus = .error
            case .authorizedWhenInUse, .authorizedAlways:
                authorizationDenied = false
                gpsStatus = .searching
                self.manager.startUpdatingLocation()
            case .notDetermined:
                self.manager.requestWhenInUseAuthorization()
            @unknown default:
                break
            }
        }
    }

    func startTracking() {
        speeds = []
        totalSpeed = 0
        averageSpeed = 0
        sessionDistance = 0
        trackingState = .tracking
    }

    func pauseTracking() {
        trackingState = .paused
    }

    func resumeTracking() {
        trackingState = .tracking
    }

    func stopTracking() {
        trackingState = .idle
    }

    func handleButtonTap() {
        switch trackingState {
        case .idle:     startTracking()
        case .tracking: pauseTracking()
        case .paused:   resumeTracking()
        }
    }

    func handleStopTap() {
        stopTracking()
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

            if let last = lastLocation {
                let segmentMiles = location.distance(from: last) * 0.000621371
                totalTripDistance += segmentMiles
                if trackingState == .tracking {
                    sessionDistance += segmentMiles
                }
            }

            lastLocation = location
            gpsStatus = .locked
            currentSpeed = mph

            if mph > 0 && trackingState == .tracking {
                totalSpeed += mph
                speeds.append(mph)
                averageSpeed = totalSpeed / Double(speeds.count)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            if clError.code == .denied {
                Task { @MainActor in
                    authorizationDenied = true
                    gpsStatus = .error
                }
            }
        }
    }
}
