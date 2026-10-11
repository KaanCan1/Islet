import Foundation
import ServiceManagement

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let store = UserDefaults.standard

    /// Show the track/timer summary either side of the notch while collapsed.
    @Published var showPeek: Bool { didSet { store.set(showPeek, forKey: "showPeek") } }
    /// Play a sound when the timer finishes.
    @Published var chimeEnabled: Bool { didSet { store.set(chimeEnabled, forKey: "chimeEnabled") } }
    /// Whether the one-time Claude consent prompt has been shown.
    @Published var claudeConsentAsked: Bool { didSet { store.set(claudeConsentAsked, forKey: "claudeConsentAsked") } }
    /// Show the Claude Code usage column in the music panel.
    @Published var showClaudeUsage: Bool { didSet { store.set(showClaudeUsage, forKey: "showClaudeUsage") } }
    /// Say so from the notch when a Claude window passes 80% and 95%, hits its
    /// limit, or comes clear again after one of those.
    @Published var claudeAlerts: Bool { didSet { store.set(claudeAlerts, forKey: "claudeAlerts") } }
    /// Keep the panel visible on the lock screen (raises the window level).
    @Published var showOnLockScreen: Bool { didSet { store.set(showOnLockScreen, forKey: "showOnLockScreen") } }
    /// Open the panel when the charger is connected or the battery runs low.
    @Published var showBatteryAlerts: Bool { didSet { store.set(showBatteryAlerts, forKey: "showBatteryAlerts") } }
    /// Catch new screenshots and keep them on the shelf to drag out.
    @Published var shelfEnabled: Bool { didSet { store.set(shelfEnabled, forKey: "shelfEnabled") } }
    /// Track head angle from AirPods and say when it has been down too long.
    @Published var postureAlerts: Bool { didSet { store.set(postureAlerts, forKey: "postureAlerts") } }
    /// The head pitch, in radians, recorded as sitting upright.
    @Published var uprightPitch: Double { didSet { store.set(uprightPitch, forKey: "uprightPitch") } }
    /// Whether `uprightPitch` means anything yet. Zero is not a usable default:
    /// a head that is level reads around -16 degrees, so measuring from zero
    /// calls you slouched before you have moved.
    @Published var postureCalibrated: Bool { didSet { store.set(postureCalibrated, forKey: "postureCalibrated") } }
    @Published var focusMinutes: Int { didSet { store.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var breakMinutes: Int { didSet { store.set(breakMinutes, forKey: "breakMinutes") } }

    private init() {
        store.register(defaults: [
            "showPeek": true,
            "showClaudeUsage": false,
            "claudeConsentAsked": false,
            "claudeAlerts": true,
            "showOnLockScreen": true,
            "showBatteryAlerts": true,
            "shelfEnabled": true,
            "postureAlerts": false,
            "uprightPitch": 0.0,
            "postureCalibrated": false,
            "chimeEnabled": true,
            "focusMinutes": 25,
            "breakMinutes": 5
        ])
        showPeek = store.bool(forKey: "showPeek")
        showClaudeUsage = store.bool(forKey: "showClaudeUsage")
        claudeConsentAsked = store.bool(forKey: "claudeConsentAsked")
        claudeAlerts = store.bool(forKey: "claudeAlerts")
        showOnLockScreen = store.bool(forKey: "showOnLockScreen")
        showBatteryAlerts = store.bool(forKey: "showBatteryAlerts")
        shelfEnabled = store.bool(forKey: "shelfEnabled")
        postureAlerts = store.bool(forKey: "postureAlerts")
        uprightPitch = store.double(forKey: "uprightPitch")
        postureCalibrated = store.bool(forKey: "postureCalibrated")
        chimeEnabled = store.bool(forKey: "chimeEnabled")
        focusMinutes = store.integer(forKey: "focusMinutes")
        breakMinutes = store.integer(forKey: "breakMinutes")
    }

    /// Posture's running totals for the current day. Plain accessors rather
    /// than published properties: they are written every half minute and
    /// nothing on screen observes them directly.
    var postureStatsDay: Double {
        get { store.double(forKey: "postureStatsDay") }
        set { store.set(newValue, forKey: "postureStatsDay") }
    }
    var postureWornSeconds: Double {
        get { store.double(forKey: "postureWornSeconds") }
        set { store.set(newValue, forKey: "postureWornSeconds") }
    }
    var postureSlouchedSeconds: Double {
        get { store.double(forKey: "postureSlouchedSeconds") }
        set { store.set(newValue, forKey: "postureSlouchedSeconds") }
    }

    /// The highest Claude alert already given for the current window, per window,
    /// so a restart does not repeat one. Plain accessors for the same reason as
    /// the posture totals: nothing on screen observes them.
    func claudeAlertLevel(for window: String) -> Int {
        store.integer(forKey: "claudeAlertLevel." + window)
    }

    func setClaudeAlertLevel(_ level: Int, for window: String) {
        store.set(level, forKey: "claudeAlertLevel." + window)
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Can fail for unsigned or ad-hoc signed builds; swallows the error and
    /// reports false so the caller can explain what happened.
    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Islet: could not change launch at login: \(error.localizedDescription)")
            return false
        }
    }
}
