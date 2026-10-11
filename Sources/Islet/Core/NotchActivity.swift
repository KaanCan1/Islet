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
    /// `window` is "5h" or "week"; `percent` is nil once the limit has been hit,
    /// when the number stops meaning anything. `resets` is already formatted.
    case claude(window: String, alert: ClaudeAlert, percent: Int?, isEstimate: Bool, resets: String?)

    enum ClaudeAlert: Equatable { case warning, critical, limit, cleared }

    /// How long it stays on screen. Posture and Claude get a beat longer: they
    /// arrive while you are looking at something else, so they have to survive
    /// being noticed late.
    var duration: TimeInterval {
        switch self {
        case .battery: return 4
        case .posture, .claude: return 6
        }
    }

    var icon: String {
        switch self {
        case .battery(let percent, let charging, let plugged, _):
            if charging { return "battery.100.bolt" }
            if plugged { return "powerplug.fill" }
            return percent <= 20 ? "battery.25" : "battery.75"
        case .posture: return "figure.seated.side"
        case .claude(_, let alert, _, _, _):
            switch alert {
            case .warning: return "gauge.medium"
            case .critical: return "gauge.high"
            case .limit: return "gauge.with.needle.fill"
            case .cleared: return "gauge.low"
            }
        }
    }

    var accent: Color {
        switch self {
        case .battery(let percent, let charging, _, _):
            if charging { return Color(red: 0.35, green: 0.85, blue: 0.45) }
            return percent <= 20 ? .red : .white
        case .posture: return Color(red: 1.0, green: 0.72, blue: 0.30)
        case .claude(_, let alert, _, _, _):
            switch alert {
            // The app's own orange, the one the timer ring uses.
            case .warning: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .critical, .limit: return .red
            case .cleared: return Color(red: 0.35, green: 0.85, blue: 0.45)
            }
        }
    }

    /// How full the bar is drawn.
    var level: Double {
        switch self {
        case .battery(let percent, _, _, _): return Double(percent) / 100
        // How far past the threshold the head is, with 45 degrees as "all the way".
        case .posture(let degrees, _): return Double(degrees) / 45
        case .claude(_, let alert, let percent, _, _):
            return alert == .limit ? 1 : Double(percent ?? 0) / 100
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
        case .claude(let window, let alert, let percent, let isEstimate, let resets):
            // An estimate wears a tilde, as it does in the panel's own ceiling.
            let amount = percent.map { (isEstimate ? "~" : "") + "\($0)%" }
            switch alert {
            case .cleared:
                return "\(window) window is clear"
            case .limit:
                return resets.map { "\(window) limit · resets \($0)" } ?? "\(window) limit"
            case .warning, .critical:
                let head = [window, amount].compactMap { $0 }.joined(separator: " · ")
                return resets.map { "\(head) · resets \($0)" } ?? head
            }
        }
    }

    /// Claude's caption carries a reset time as well, so it needs the room.
    var contentWidth: CGFloat {
        switch self {
        case .claude: return 272
        default: return 236
        }
    }

    /// Which preference has to be on for this to be shown at all.
    @MainActor
    var isEnabled: Bool {
        switch self {
        case .battery: return Preferences.shared.showBatteryAlerts
        case .posture: return Preferences.shared.postureAlerts
        case .claude: return Preferences.shared.showClaudeUsage && Preferences.shared.claudeAlerts
        }
    }
}
