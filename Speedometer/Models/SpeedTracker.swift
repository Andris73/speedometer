import CoreLocation
import Foundation

@MainActor
final class SpeedTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum GPSStatus { case searching, locked, error }

    private let manager = CLLocationManager()

    /// Live speed in mph. Always updated from GPS, regardless of session state.
    @Published var currentSpeed: Double = 0
    /// Session average speed in mph, computed as session distance / elapsed time.
    @Published var averageSpeed: Double = 0
    /// Distance travelled during the current/last session, in miles.
    @Published var sessionDistance: Double = 0
    /// Elapsed duration of the current/last session, in seconds.
    @Published var elapsedTime: TimeInterval = 0
    /// True while a session is actively running (Start pressed, Stop not yet pressed).
    @Published var isRunning = false
    /// True once a session has completed, so the last results stay visible until the next Start.
    @Published var hasResults = false
    @Published var gpsStatus: GPSStatus = .searching
    @Published var authorizationDenied = false

    private var lastLocation: CLLocation?
    private var sessionStartDate: Date?
    private var timer: Timer?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Authorization

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

    // MARK: - Start / Stop

    /// Toggles the averaging session: Start begins a fresh session, Stop ends it.
    func handleButtonTap() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        sessionDistance = 0
        elapsedTime = 0
        averageSpeed = 0
        sessionStartDate = Date()
        hasResults = false
        isRunning = true
        startTimer()
    }

    private func stop() {
        isRunning = false
        hasResults = true
        stopTimer()
        // elapsedTime, sessionDistance and averageSpeed are intentionally left
        // untouched so the last results stay visible until the next Start.
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isRunning, let start = sessionStartDate else { return }
        elapsedTime = Date().timeIntervalSince(start)
        recomputeAverage()
    }

    /// Average speed (mph) = session distance (miles) / elapsed time (hours).
    private func recomputeAverage() {
        let hours = elapsedTime / 3600.0
        averageSpeed = hours > 0 ? sessionDistance / hours : 0
    }

    // MARK: - Speed computation

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

            if let last = lastLocation, isRunning {
                let segmentMiles = location.distance(from: last) * 0.000621371
                sessionDistance += segmentMiles
            }

            lastLocation = location
            gpsStatus = .locked
            currentSpeed = mph

            if isRunning, let start = sessionStartDate {
                elapsedTime = Date().timeIntervalSince(start)
                recomputeAverage()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .denied {
            Task { @MainActor in
                authorizationDenied = true
                gpsStatus = .error
            }
        }
    }
}
