import SwiftUI

/// A short-lived alert the notch shows on its own, with no user interaction.
/// Adding a case means supplying `duration`, `icon`, `accent`, `level`,
/// `caption` and `contentWidth`.
///
/// Volume and brightness deliberately aren't here: macOS already draws its own
/// HUD for both, and duplicating it added noise rather than information.
enum NotchActivity: Equatable {
    case battery(percent: Int, charging: Bool, plugged: Bool, minutes: Int)
    case posture(degrees: Int, minutes: Int)

    /// How long it stays on screen. Posture gets a beat longer: it arrives while
    /// you are looking at something else, so it has to survive being noticed late.
    var duration: TimeInterval {
        switch self {
        case .battery: return 4
        case .posture: return 6
        }
    }

    var icon: String {
        switch self {
        case .battery(let percent, let charging, let plugged, _):
            if charging { return "battery.100.bolt" }
            if plugged { return "powerplug.fill" }
            return percent <= 20 ? "battery.25" : "battery.75"
        case .posture: return "figure.seated.side"
        }
    }

    var accent: Color {
        switch self {
        case .battery(let percent, let charging, _, _):
            if charging { return Color(red: 0.35, green: 0.85, blue: 0.45) }
            return percent <= 20 ? .red : .white
        case .posture: return Color(red: 1.0, green: 0.72, blue: 0.30)
        }
    }

    /// How full the bar is drawn.
    var level: Double {
        switch self {
        case .battery(let percent, _, _, _): return Double(percent) / 100
        // How far past the threshold the head is, with 45 degrees as "all the way".
        case .posture(let degrees, _): return Double(degrees) / 45
        }
    }

    /// Text shown to the right of the bar.
    var caption: String? {
        switch self {
        case .battery(let percent, let charging, let plugged, let minutes):
            if charging { return "\(percent)% · charging" }
            if plugged { return "\(percent)% · plugged in" }
            if minutes > 0 { return "\(percent)% · \(minutes / 60)h \(minutes % 60)m left" }
            return "\(percent)%"
        case .posture(let degrees, let minutes):
            return "head down \(degrees)° · \(minutes) min"
        }
    }

    var contentWidth: CGFloat { 236 }

    /// Which preference has to be on for this to be shown at all.
    @MainActor
    var isEnabled: Bool {
        switch self {
        case .battery: return Preferences.shared.showBatteryAlerts
        case .posture: return Preferences.shared.postureAlerts
        }
    }
}
