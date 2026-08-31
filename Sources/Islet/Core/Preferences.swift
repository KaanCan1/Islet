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
    /// Keep the panel visible on the lock screen (raises the window level).
    @Published var showOnLockScreen: Bool { didSet { store.set(showOnLockScreen, forKey: "showOnLockScreen") } }
    /// Open the panel when the charger is connected or the battery runs low.
    @Published var showBatteryAlerts: Bool { didSet { store.set(showBatteryAlerts, forKey: "showBatteryAlerts") } }
    @Published var focusMinutes: Int { didSet { store.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var breakMinutes: Int { didSet { store.set(breakMinutes, forKey: "breakMinutes") } }

    private init() {
        store.register(defaults: [
            "showPeek": true,
            "showOnLockScreen": true,
            "showBatteryAlerts": true,
            "chimeEnabled": true,
            "focusMinutes": 25,
            "breakMinutes": 5
        ])
        showPeek = store.bool(forKey: "showPeek")
        showOnLockScreen = store.bool(forKey: "showOnLockScreen")
        showBatteryAlerts = store.bool(forKey: "showBatteryAlerts")
        chimeEnabled = store.bool(forKey: "chimeEnabled")
        focusMinutes = store.integer(forKey: "focusMinutes")
        breakMinutes = store.integer(forKey: "breakMinutes")
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
