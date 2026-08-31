import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = NotchController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Islet"
        )
        item.button?.image?.isTemplate = true
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(withTitle: "Music", action: #selector(openMusic), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Timer", action: #selector(openTimer), keyEquivalent: "").target = self
        menu.addItem(.separator())

        addToggle(to: menu, title: "Peek beside the notch", id: "peek", action: #selector(togglePeek))
        addToggle(to: menu, title: "Track progress around the notch", id: "ring", action: #selector(toggleRing))
        addToggle(to: menu, title: "Show on lock screen", id: "lock", action: #selector(toggleLockScreen))
        addToggle(to: menu, title: "Battery and charging alerts", id: "battery", action: #selector(toggleBattery))
        addToggle(to: menu, title: "Timer chime", id: "chime", action: #selector(toggleChime))
        addToggle(to: menu, title: "Launch at login", id: "login", action: #selector(toggleLogin))

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Islet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func addToggle(to menu: NSMenu, title: String, id: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.identifier = NSUserInterfaceItemIdentifier(id)
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func openMusic() { controller.open(tab: .music) }
    @objc private func openTimer() { controller.open(tab: .timer) }
    @objc private func togglePeek() { Preferences.shared.showPeek.toggle() }
    @objc private func toggleChime() { Preferences.shared.chimeEnabled.toggle() }
    @objc private func toggleRing() { Preferences.shared.showProgressRing.toggle() }
    @objc private func toggleBattery() { Preferences.shared.showBatteryAlerts.toggle() }

    @objc private func toggleLockScreen() {
        Preferences.shared.showOnLockScreen.toggle()
        controller.applyWindowLevel()
    }

    @objc private func toggleLogin() {
        let prefs = Preferences.shared
        if !prefs.setLaunchAtLogin(!prefs.launchAtLogin) {
            let alert = NSAlert()
            alert.messageText = "Couldn't change launch at login"
            alert.informativeText = "macOS only allows this for apps installed in /Applications."
            alert.runModal()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let prefs = Preferences.shared
        for item in menu.items {
            switch item.identifier?.rawValue {
            case "peek": item.state = prefs.showPeek ? .on : .off
            case "ring": item.state = prefs.showProgressRing ? .on : .off
            case "lock": item.state = prefs.showOnLockScreen ? .on : .off
            case "battery": item.state = prefs.showBatteryAlerts ? .on : .off
            case "chime": item.state = prefs.chimeEnabled ? .on : .off
            case "login": item.state = prefs.launchAtLogin ? .on : .off
            default: break
            }
        }
    }
}
