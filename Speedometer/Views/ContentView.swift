import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = SpeedTracker()
    @AppStorage("useMetric") private var useMetric = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var unitFactor: Double { useMetric ? 1.60934 : 1 }
    private var unitLabel: String { useMetric ? "km/h" : "mph" }
    private var displaySpeed: Double { tracker.currentSpeed * unitFactor }
    private var displayAverage: Double { tracker.averageSpeed * unitFactor }
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { geometry in
            let speedFontSize = max(40, min(80, geometry.size.height * 0.3))
            VStack(spacing: isLandscape ? 8 : 24) {
                if tracker.authorizationDenied {
                    Spacer()
                    Text("Location access denied")
                        .foregroundStyle(.red)
                        .font(.title3)
                    Spacer()
                } else {
                    Spacer(minLength: 0)

                    speedDisplay(fontSize: speedFontSize)

                    if !isLandscape {
                        Spacer(minLength: 0)
                    }

                    statusLabel

                    Button(action: toggleTracking) {
                        Text(tracker.isTracking ? "Stop" : "Start")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, isLandscape ? 10 : 16)
                            .background(tracker.isTracking ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .padding(.horizontal, isLandscape ? 40 : 60)
                    }
                    .disabled(tracker.authorizationDenied)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, isLandscape ? 4 : 16)
        }
    }

    private func speedDisplay(fontSize: CGFloat) -> some View {
        VStack(spacing: isLandscape ? 0 : 4) {
            Text(tracker.isTracking ? "AVERAGE" : "CURRENT")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f", tracker.isTracking ? displayAverage : displaySpeed))
                .font(.system(size: fontSize, weight: .thin, design: .monospaced))
                .modifier(NumericContentTransition())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .animation(.default, value: tracker.isTracking ? displayAverage : displaySpeed)
            unitButton
        }
    }

    private var unitButton: some View {
        Button(action: { useMetric.toggle() }) {
            Text(unitLabel)
                .font(isLandscape ? .callout : .title3)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if tracker.isTracking {
            Label("Tracking average", systemImage: "dot.radiowaves.left.and.right")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text("Press Start to track")
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
