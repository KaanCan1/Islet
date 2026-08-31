import SwiftUI

/// A short-lived alert the notch shows on its own, with no user interaction.
/// Battery is the only one today; adding a case means supplying `duration`,
/// `icon`, `accent`, `level`, `caption` and `contentWidth`.
///
/// Volume and brightness deliberately aren't here: macOS already draws its own
/// HUD for both, and duplicating it added noise rather than information.
enum NotchActivity: Equatable {
    case battery(percent: Int, charging: Bool, plugged: Bool, minutes: Int)

    /// How long it stays on screen.
    var duration: TimeInterval { 4 }

    var icon: String {
        switch self {
        case .battery(let percent, let charging, let plugged, _):
            if charging { return "battery.100.bolt" }
            if plugged { return "powerplug.fill" }
            return percent <= 20 ? "battery.25" : "battery.75"
        }
    }

    var accent: Color {
        switch self {
        case .battery(let percent, let charging, _, _):
            if charging { return Color(red: 0.35, green: 0.85, blue: 0.45) }
            return percent <= 20 ? .red : .white
        }
    }

    /// How full the bar is drawn.
    var level: Double {
        switch self {
        case .battery(let percent, _, _, _): return Double(percent) / 100
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
        }
    }

    var contentWidth: CGFloat { 236 }
}
