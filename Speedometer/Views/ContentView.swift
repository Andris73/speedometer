import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = SpeedTracker()

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            if tracker.currentSpeed < 0 {
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
            .disabled(tracker.currentSpeed < 0)

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
                Text(String(format: "%.1f", tracker.averageSpeed))
                    .font(.system(size: 80, weight: .thin, design: .monospaced))
                    .modifier(NumericContentTransition())
                    .animation(.default, value: tracker.averageSpeed)
                Text("mph")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 4) {
                Text("CURRENT")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f", tracker.currentSpeed))
                    .font(.system(size: 80, weight: .thin, design: .monospaced))
                    .modifier(NumericContentTransition())
                    .animation(.default, value: tracker.currentSpeed)
                Text("mph")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
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
