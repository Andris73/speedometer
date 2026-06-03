import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = SpeedTracker()
    @AppStorage("useMetric") private var useMetric = false
    @AppStorage("colorSchemePreference") private var colorSchemePreference = 0
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var unitFactor: Double { useMetric ? 1.60934 : 1 }
    private var unitLabel: String { useMetric ? "km/h" : "mph" }
    private var displaySpeed: Double { tracker.currentSpeed * unitFactor }
    private var displayAverage: Double { tracker.averageSpeed * unitFactor }
    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var preferredScheme: ColorScheme? {
        switch colorSchemePreference {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: isLandscape ? 6 : 12) {
                topBar

                if tracker.authorizationDenied {
                    Spacer()
                    Text("Location access denied")
                        .foregroundStyle(.red)
                        .font(.title3)
                    Spacer()
                } else {
                    if isLandscape {
                        landscapeSpeedPanels(geometry: geometry)
                    } else {
                        portraitSpeedPanels(geometry: geometry)
                    }

                    controlButton(geometry: geometry)

                    distanceRow
                }
            }
            .padding(.horizontal, isLandscape ? 16 : 20)
            .padding(.vertical, isLandscape ? 6 : 12)
        }
        .preferredColorScheme(preferredScheme)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var topBar: some View {
        HStack {
            gpsDot
            Spacer()
            themeButton
            unitToggle
        }
        .font(.callout)
    }

    private var gpsDot: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(gpsColor)
                .frame(width: 10, height: 10)
            Text(gpsLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var gpsColor: Color {
        switch tracker.gpsStatus {
        case .locked:    return .green
        case .searching: return .yellow
        case .error:     return .red
        }
    }

    private var gpsLabel: String {
        switch tracker.gpsStatus {
        case .locked:    return "Locked"
        case .searching: return "Searching"
        case .error:     return "No GPS"
        }
    }

    private var themeButton: some View {
        Button(action: {
            colorSchemePreference = (colorSchemePreference + 1) % 3
        }) {
            Image(systemName: colorSchemePreference == 2 ? "moon.fill" : "sun.max.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var unitToggle: some View {
        Button(action: { useMetric.toggle() }) {
            Text(unitLabel)
                .font(.callout.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private func landscapeSpeedPanels(geometry: GeometryProxy) -> some View {
        let panelWidth = (geometry.size.width - 16) / 2
        let fontSize = max(48, min(96, panelWidth * 0.22))

        return HStack(spacing: 16) {
            speedPanel(
                label: "CURRENT",
                value: displaySpeed,
                fontSize: fontSize,
                prominent: true
            )
            speedPanel(
                label: "AVERAGE",
                value: displayAverage,
                fontSize: fontSize * 0.75,
                prominent: tracker.trackingState != .idle
            )
        }
        .frame(maxHeight: .infinity)
    }

    private func portraitSpeedPanels(geometry: GeometryProxy) -> some View {
        let availableHeight = geometry.size.height - 160
        let fontSize = max(40, min(80, availableHeight * 0.3))

        return VStack(spacing: 4) {
            speedPanel(
                label: "CURRENT",
                value: displaySpeed,
                fontSize: fontSize,
                prominent: true
            )
            speedPanel(
                label: "AVERAGE",
                value: displayAverage,
                fontSize: fontSize * 0.65,
                prominent: tracker.trackingState != .idle
            )
        }
        .frame(maxHeight: .infinity)
    }

    private func speedPanel(label: String, value: Double, fontSize: CGFloat, prominent: Bool) -> some View {
        VStack(spacing: isLandscape ? 0 : 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f", value))
                .font(.system(size: fontSize, weight: .thin, design: .monospaced))
                .modifier(NumericContentTransition())
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .animation(.default, value: value)
            Text(unitLabel)
                .font(isLandscape ? .callout : .subheadline)
                .foregroundStyle(.tertiary)
        }
        .opacity(prominent ? 1 : 0.4)
    }

    private func controlButton(geometry: GeometryProxy) -> some View {
        let buttonHeight: CGFloat = isLandscape ? 40 : 48
        return Group {
            switch tracker.trackingState {
            case .idle:
                Button(action: { tracker.handleButtonTap() }) {
                    Text("Start")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                }
                .background(Color.green)
                .clipShape(Capsule())

            case .tracking:
                HStack(spacing: 0) {
                    Button(action: { tracker.handleButtonTap() }) {
                        Text("Pause")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: buttonHeight)
                    }
                    .background(Color.orange)

                    Rectangle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 1)

                    Button(action: { tracker.handleStopTap() }) {
                        Text("Stop")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: buttonHeight)
                    }
                    .background(Color.red)
                }
                .fixedSize(horizontal: false, vertical: true)
                .clipShape(Capsule())

            case .paused:
                HStack(spacing: 0) {
                    Button(action: { tracker.handleButtonTap() }) {
                        Text("Resume")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: buttonHeight)
                    }
                    .background(Color.green)

                    Rectangle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 1)

                    Button(action: { tracker.handleStopTap() }) {
                        Text("Stop")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: buttonHeight)
                    }
                    .background(Color.red)
                }
                .fixedSize(horizontal: false, vertical: true)
                .clipShape(Capsule())
            }
        }
        .disabled(tracker.authorizationDenied)
        .padding(.horizontal, isLandscape ? 0 : 20)
    }

    private var distanceRow: some View {
        HStack(spacing: 4) {
            Text("Trip:")
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f", tracker.totalTripDistance * unitFactor))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
            Text(unitLabel)
                .foregroundStyle(.tertiary)

            Text(" • ")
                .foregroundStyle(.quaternary)

            Text("Session:")
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f", tracker.sessionDistance * unitFactor))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
            Text(unitLabel)
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
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
