import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = SpeedTracker()
    @AppStorage("useMetric") private var useMetric = false

    private var unitFactor: Double { useMetric ? 1.60934 : 1 }
    private var unitLabel: String { useMetric ? "km/h" : "mph" }
    private var displaySpeed: Double { tracker.currentSpeed * unitFactor }
    private var displayAverage: Double { tracker.averageSpeed * unitFactor }

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            if tracker.authorizationDenied {
                Text("Location access denied")
                    .foregroundStyle(.red)
                    .font(.title3)
            } else {
                speedDisplay
            }

            Spacer()

            statusLabel

            Button(action: toggleTracking) {
                Text(tracker.isTracking ? "Stop" : "Start")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(tracker.isTracking ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(.horizontal, 60)
            }
            .disabled(tracker.authorizationDenied)

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var speedDisplay: some View {
        if tracker.isTracking {
            VStack(spacing: 4) {
                Text("AVERAGE")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f", displayAverage))
                    .font(.system(size: 80, weight: .thin, design: .monospaced))
                    .modifier(NumericContentTransition())
                    .animation(.default, value: displayAverage)
                unitButton
            }
        } else {
            VStack(spacing: 4) {
                Text("CURRENT")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f", displaySpeed))
                    .font(.system(size: 80, weight: .thin, design: .monospaced))
                    .modifier(NumericContentTransition())
                    .animation(.default, value: displaySpeed)
                unitButton
            }
        }
    }

    private var unitButton: some View {
        Button(action: { useMetric.toggle() }) {
            Text(unitLabel)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if tracker.isTracking {
            Label("Tracking average speed…", systemImage: "dot.radiowaves.left.and.right")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text("Press Start to track average speed")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func toggleTracking() {
        if tracker.isTracking {
            tracker.stopTrackingAverage()
        } else {
            tracker.startTrackingAverage()
        }
    }
}

struct NumericContentTransition: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.contentTransition(.numericText())
        } else {
            content
        }
    }
}
