import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = NotchController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        setupStatusItem()
        controller.onContextMenu = { [weak self] point in self?.showMenu(at: point) }
        askAboutClaudeIfNeeded()
    }

    /// macOS does not gate `~/.claude`, so nothing would stop Islet reading it
    /// silently. Ask once instead, and leave the feature off unless told otherwise.
    private func askAboutClaudeIfNeeded() {
        let prefs = Preferences.shared
        guard !prefs.claudeConsentAsked else { return }
        prefs.claudeConsentAsked = true

        let transcripts = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard FileManager.default.fileExists(atPath: transcripts.path) else { return }

        let alert = NSAlert()
        alert.messageText = "Show your Claude Code usage?"
        alert.informativeText = "Islet can show how much of the current Claude Code window you have used, "
            + "beside the music controls.\n\n"
            + "To do that it reads ~/.claude/projects on this Mac: timestamps, token counts and model "
            + "names only. It never reads the contents of your conversations, and nothing is sent anywhere.\n\n"
            + "You can change this at any time from the menu bar."
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Not now")
        alert.alertStyle = .informational

        NSApp.activate(ignoringOtherApps: true)
        prefs.showClaudeUsage = alert.runModal() == .alertFirstButtonReturn
        controller.updateClaudeMonitor()
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

    /// A fresh menu each time rather than the status item's own: that one belongs
    /// to the status item, and popping it up from somewhere else fights it for
    /// ownership. Building it again is cheap and keeps both in step.
    private func showMenu(at point: NSPoint) {
        buildMenu().popUp(positioning: nil, at: point, in: nil)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        // Otherwise AppKit enables every item with a target and ignores the
        // Claude alerts item being greyed out below.
        menu.autoenablesItems = false

        menu.addItem(withTitle: "Music", action: #selector(openMusic), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Timer", action: #selector(openTimer), keyEquivalent: "").target = self
        menu.addItem(.separator())

        addToggle(to: menu, title: "Peek beside the notch", id: "peek", action: #selector(togglePeek))
        addToggle(to: menu, title: "Claude usage in the music panel", id: "claude", action: #selector(toggleClaude))
        addToggle(to: menu, title: "Claude limit alerts", id: "claudeAlerts", action: #selector(toggleClaudeAlerts))
        addToggle(to: menu, title: "Show on lock screen", id: "lock", action: #selector(toggleLockScreen))
        addToggle(to: menu, title: "Battery and charging alerts", id: "battery", action: #selector(toggleBattery))
        addToggle(to: menu, title: "Screenshot shelf", id: "shelf", action: #selector(toggleShelf))
        addToggle(to: menu, title: "Posture alerts (AirPods)", id: "posture", action: #selector(togglePosture))
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
    @objc private func toggleClaude() {
        Preferences.shared.showClaudeUsage.toggle()
        controller.updateClaudeMonitor()
    }
    @objc private func toggleClaudeAlerts() { Preferences.shared.claudeAlerts.toggle() }
    @objc private func toggleBattery() { Preferences.shared.showBatteryAlerts.toggle() }

    @objc private func toggleShelf() {
        Preferences.shared.shelfEnabled.toggle()
        controller.updateShelfWatcher()
    }

    /// Turning this on is left to stand even with nothing connected: AirPods come
    /// and go, and Islet picks them up when they do. The alert only explains why
    /// nothing has appeared yet.
    @objc private func togglePosture() {
        let prefs = Preferences.shared
        prefs.postureAlerts.toggle()
        controller.updatePostureMonitor()

        guard prefs.postureAlerts, !controller.state.posture.isSupported else { return }
        let alert = NSAlert()
        alert.messageText = "No headphones reporting head motion"
        alert.informativeText = "Posture tracking reads the head angle from AirPods Pro, AirPods (3rd "
            + "generation) or AirPods Max. Islet will start as soon as a pair is connected.\n\n"
            + "Open the panel afterwards and press \"Set upright\" while sitting how you mean to sit — "
            + "every reading is measured from that."
        alert.alertStyle = .informational
        alert.runModal()
    }

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
            case "lock": item.state = prefs.showOnLockScreen ? .on : .off
            case "claude": item.state = prefs.showClaudeUsage ? .on : .off
            case "claudeAlerts":
                item.state = prefs.claudeAlerts ? .on : .off
                // Alerts read the same figures, so they mean nothing without them.
                item.isEnabled = prefs.showClaudeUsage
            case "battery": item.state = prefs.showBatteryAlerts ? .on : .off
            case "shelf": item.state = prefs.shelfEnabled ? .on : .off
            case "posture": item.state = prefs.postureAlerts ? .on : .off
            case "chime": item.state = prefs.chimeEnabled ? .on : .off
            case "login": item.state = prefs.launchAtLogin ? .on : .off
            default: break
            }
        }
    }
}
