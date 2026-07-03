import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = SpeedTracker()
    @StateObject private var pip = SpeedPiPManager()
    @AppStorage("useMetric") private var useMetric = false
    @AppStorage("colorSchemePreference") private var colorSchemePreference = 0
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var systemColorScheme

    private var unitFactor: Double { useMetric ? 1.60934 : 1 }
    private var speedUnitLabel: String { useMetric ? "KPH" : "MPH" }
    private var distanceUnitLabel: String { useMetric ? "km" : "mi" }
    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var preferredScheme: ColorScheme? {
        switch colorSchemePreference {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    /// The scheme actually shown: a manual override if set, otherwise the system scheme.
    private var isDarkMode: Bool {
        switch colorSchemePreference {
        case 1: return false
        case 2: return true
        default: return systemColorScheme == .dark
        }
    }

    /// Whole-number speed in the selected unit, capped at 3 characters (Req 13 & 14).
    private func speedString(_ mph: Double) -> String {
        let value = (mph * unitFactor).rounded()
        let clamped = min(999, max(0, Int(value)))
        return String(clamped)
    }

    private var displayDistance: Double { tracker.sessionDistance * unitFactor }

    /// Elapsed session duration formatted as HH:MM:SS (Req 10).
    private func elapsedString(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// Results stay at full opacity while running and after a completed session (Req 9).
    private var resultsProminent: Bool { tracker.isRunning || tracker.hasResults }

    var body: some View {
        ZStack {
            // Full-bleed background reaches the physical edges...
            Color(.systemBackground)
                .ignoresSafeArea()

            // ...while the content respects the safe area natively, keeping the
            // top bar clear of the status bar / notch and the control clear of
            // the home indicator.
            GeometryReader { geometry in
                VStack(spacing: isLandscape ? 8 : 16) {
                    topBar

                    if tracker.authorizationDenied {
                        Spacer()
                        Text("Location access denied")
                            .foregroundStyle(.red)
                            .font(.title3)
                        Spacer()
                    } else {
                        if isLandscape {
                            landscapeContent(geometry: geometry)
                        } else {
                            portraitContent(geometry: geometry)
                        }

                        controlButton
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .padding(.horizontal, isLandscape ? 24 : 20)
            .padding(.vertical, 8)
        }
        .background(PiPHostView(manager: pip).frame(width: 1, height: 1), alignment: .topLeading)
        .preferredColorScheme(preferredScheme)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            pip.onSetPlaying = { playing in
                if playing != tracker.isRunning {
                    tracker.handleButtonTap()
                }
            }
            pip.bind(
                speed: tracker.$currentSpeed,
                average: tracker.$averageSpeed,
                isRunning: tracker.$isRunning
            )
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: useMetric) { _ in pip.refresh() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(gpsColor)
                .padding(8)
                .accessibilityLabel(gpsAccessibilityLabel)
            Spacer()
            if pip.isSupported {
                pipButton
            }
            themeButton
        }
        .padding(.horizontal, 8)
    }

    private var pipButton: some View {
        Button {
            pip.refresh()
            pip.toggle()
        } label: {
            Image(systemName: pip.isActive ? "pip.exit" : "pip.enter")
                .font(.title3)
                .foregroundStyle(pip.isActive ? Color.accentColor : Color.secondary)
                .padding(8)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(pip.isActive ? "Exit Picture in Picture" : "Enter Picture in Picture")
    }

    private var gpsColor: Color {
        switch tracker.gpsStatus {
        case .locked:    return .green
        case .searching: return .yellow
        case .error:     return .red
        }
    }

    private var gpsAccessibilityLabel: String {
        switch tracker.gpsStatus {
        case .locked:    return "GPS locked"
        case .searching: return "GPS searching"
        case .error:     return "No GPS"
        }
    }

    private var themeButton: some View {
        Button {
            colorSchemePreference = (colorSchemePreference + 1) % 3
        } label: {
            Image(systemName: colorSchemePreference == 2 ? "moon.fill" : "sun.max.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(8)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Layouts

    /// Landscape: split the screen into two halves and centre the live speed in
    /// the left half and the average in the right half (Req 2).
    private func landscapeContent(geometry: GeometryProxy) -> some View {
        let currentFont = geometry.size.height * 0.50
        let averageFont = geometry.size.height * 0.36
        return HStack(spacing: 0) {
            speedColumn(
                label: "CURRENT",
                value: speedString(tracker.currentSpeed),
                fontSize: currentFont,
                prominent: true
            )
            .frame(maxWidth: .infinity)

            averageColumn(fontSize: averageFont)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Portrait: live speed on top, average stacked below (Req 3).
    private func portraitContent(geometry: GeometryProxy) -> some View {
        let currentFont = geometry.size.height * 0.20
        let averageFont = geometry.size.height * 0.13
        return VStack(spacing: 24) {
            speedColumn(
                label: "CURRENT",
                value: speedString(tracker.currentSpeed),
                fontSize: currentFont,
                prominent: true
            )
            averageColumn(fontSize: averageFont)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func averageColumn(fontSize: CGFloat) -> some View {
        VStack(spacing: isLandscape ? 2 : 8) {
            speedColumn(
                label: "AVERAGE",
                value: speedString(tracker.averageSpeed),
                fontSize: fontSize,
                prominent: resultsProminent
            )
            elapsedAndDistance
                .opacity(resultsProminent ? 1 : 0.4)
        }
    }

    private func speedColumn(label: String, value: String, fontSize: CGFloat, prominent: Bool) -> some View {
        VStack(spacing: isLandscape ? 0 : 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            unitButton
        }
        .opacity(prominent ? 1 : 0.4)
    }

    /// Tappable units label that toggles MPH <-> KPH and live-converts (Req 5 & 6).
    private var unitButton: some View {
        Button {
            useMetric.toggle()
        } label: {
            Text(speedUnitLabel)
                .font(isLandscape ? .callout : .headline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    /// Elapsed time (HH:MM:SS) and session distance below the average (Req 10 & 11).
    private var elapsedAndDistance: some View {
        VStack(spacing: 2) {
            Text(elapsedString(tracker.elapsedTime))
                .font(.title3.monospacedDigit())
                .foregroundStyle(.primary)
            Text("\(String(format: "%.1f", displayDistance)) \(distanceUnitLabel)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Control

    /// Start is green in light mode but a low-glare dark grey in dark mode to
    /// avoid distraction at night; Stop stays red.
    private var controlButtonColor: Color {
        if tracker.isRunning {
            return .red
        }
        return isDarkMode ? Color(white: 0.22) : Color.green
    }

    /// Single Start/Stop toggle (Req 7).
    private var controlButton: some View {
        Button {
            tracker.handleButtonTap()
        } label: {
            Text(tracker.isRunning ? "Stop" : "Start")
                .font(.title2.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: isLandscape ? 44 : 56)
        }
        .background(controlButtonColor)
        .clipShape(Capsule())
        .disabled(tracker.authorizationDenied)
    }
}
