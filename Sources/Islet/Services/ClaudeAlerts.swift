import Foundation

/// Decides when a Claude usage window is worth mentioning without being asked:
/// crossing 80% and 95% of it, being cut off, and coming clear again after one
/// of those. Each is said once per window.
///
/// What has been said is kept in preferences, so a restart at 85% does not
/// announce 80% a second time. A new window is recognised by its percentage
/// falling back below half rather than by its reset time: the local estimate
/// infers that time and can move it by minutes between scans, while usage
/// inside a window only ever climbs.
@MainActor
final class ClaudeAlerts {
    enum Window: String {
        case fiveHour = "5h", sevenDay = "week"
    }

    enum Level: Int, Comparable {
        case none = 0, warning = 80, critical = 95, limit = 100
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    enum Decision: Equatable {
        case stay
        /// Forget what was said without saying anything: a window that only
        /// reached a warning has turned over, which is not news.
        case rearm
        case announce(Level)
        case cleared
    }

    /// A window at this fraction or lower, having been warned about, has turned over.
    static let rearmBelow = 0.5

    /// Asked to put the alert on screen. Returns whether it got there; one that
    /// did not is tried again on the next reading instead of being marked said.
    var onAlert: ((Window, NotchActivity.ClaudeAlert, ClaudeWindow) -> Bool)?

    func check(_ snapshot: ClaudeUsageMonitor.Snapshot) {
        check(.fiveHour, snapshot.fiveHour)
        check(.sevenDay, snapshot.sevenDay)
    }

    private func check(_ id: Window, _ window: ClaudeWindow) {
        let prefs = Preferences.shared
        let said = Level(rawValue: prefs.claudeAlertLevel(for: id.rawValue)) ?? .none

        switch Self.decide(said: said, window: window) {
        case .stay:
            return
        case .rearm:
            prefs.setClaudeAlertLevel(Level.none.rawValue, for: id.rawValue)
        case .cleared:
            if onAlert?(id, .cleared, window) == true {
                prefs.setClaudeAlertLevel(Level.none.rawValue, for: id.rawValue)
            }
        case .announce(let level):
            let alert: NotchActivity.ClaudeAlert = switch level {
            case .limit: .limit
            case .critical: .critical
            default: .warning
            }
            if onAlert?(id, alert, window) == true {
                prefs.setClaudeAlertLevel(level.rawValue, for: id.rawValue)
            }
        }
    }

    /// The whole rule, free of preferences and the screen.
    nonisolated static func decide(said: Level, window: ClaudeWindow) -> Decision {
        let reached: Level
        if window.limitReached {
            reached = .limit
        } else if let percent = window.percent {
            if said != .none, percent < rearmBelow {
                return said >= .critical ? .cleared : .rearm
            }
            let whole = Int((percent * 100).rounded())
            reached = whole >= Level.critical.rawValue ? .critical
                : whole >= Level.warning.rawValue ? .warning : .none
        } else {
            // No percentage yet: the estimate has not seen two cut-offs. Nothing
            // to measure against, so nothing to say.
            return .stay
        }
        return reached > said ? .announce(reached) : .stay
    }
}
