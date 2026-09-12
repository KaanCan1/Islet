import AppKit
import SwiftUI

/// Owns the panel, follows screen changes, and opens or closes it based on where
/// the cursor is.
@MainActor
final class NotchController {
    let state = NotchState()

    private var panel: NotchPanel?
    private var hoverTimer: Timer?
    private let battery = BatteryMonitor()
    private let screenshots = ScreenshotWatcher()
    private var rightClickMonitor: Any?

    /// Right-clicking the open panel asks for the settings menu.
    ///
    /// The menu bar icon cannot be relied on as the only way in: on a crowded
    /// menu bar — and a notch leaves half of one — macOS hides the items that do
    /// not fit, without saying so, and a newly added item is the first to go.
    /// The notch itself is always there, so it carries the same menu.
    var onContextMenu: ((NSPoint) -> Void)?

    func start() {
        rebuild()
        state.music.start()
        startMonitors()

        // Documentation hook: ISLET_DEMO=music|timer holds the panel open on one
        // tab so screenshots for the README are reproducible. Deliberately time
        // limited — a panel stuck open forever is worse than a missed capture.
        if let demo = ProcessInfo.processInfo.environment["ISLET_DEMO"] {
            state.tab = NotchState.Tab(rawValue: demo.lowercased()) ?? .music
            state.forceExpandUntil = Date().addingTimeInterval(120)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer

        // Returns a plain Bool rather than the event itself: handing an NSEvent
        // back across the isolation boundary is an error under Swift 6.
        startStateLogIfAsked()

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            let swallowed = MainActor.assumeIsolated { () -> Bool in
                guard let self, let panel = self.panel,
                      event.window === panel, self.state.isExpanded else { return false }
                // Hold the panel open: the menu takes the cursor with it, and
                // without this the panel collapses out from under its own menu.
                self.state.interactionLocked = true
                self.onContextMenu?(NSEvent.mouseLocation)
                self.state.interactionLocked = false
                return true
            }
            return swallowed ? nil : event
        }
    }

    // MARK: - System alerts

    private func startMonitors() {
        // macOS already draws its own HUD for volume and brightness, so the only
        // thing worth surfacing here is what it doesn't: battery events.
        battery.onEvent = { [weak self] snapshot in
            self?.state.present(.battery(
                percent: snapshot.percent,
                charging: snapshot.isCharging,
                plugged: snapshot.isPlugged,
                minutes: snapshot.minutes
            ))
        }
        battery.start()

        // A new screenshot pops the shelf open for a few seconds. That window is
        // the whole feature: macOS's own thumbnail cannot be dragged once it has
        // faded, and this one can — and it stays on the shelf afterwards.
        screenshots.onCapture = { [weak self] url in
            guard let self else { return }
            self.state.shelf.add(url)
            self.revealShelf()
        }

        state.posture.onSlouch = { [weak self] minutes in
            guard let self, let drop = self.state.posture.drop else { return false }
            return self.state.present(.posture(degrees: Int(drop.rounded()), minutes: minutes))
        }

        updateClaudeMonitor()
        updateShelfWatcher()
        updatePostureMonitor()
    }

    /// ISLET_STATE_LOG=<file> appends what the posture monitor is actually doing
    /// inside the running app. --posture cannot answer that: only one process at
    /// a time receives headphone motion, so a probe started alongside the app is
    /// starved and reports nothing.
    private func startStateLogIfAsked() {
        guard let path = ProcessInfo.processInfo.environment["ISLET_STATE_LOG"], !path.isEmpty
        else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let posture = self.state.posture
                let drop = posture.drop.map { String(format: "%+.1f°", $0) } ?? "—"
                let line = "\(Date().formatted(date: .omitted, time: .standard))"
                    + "  availability=\(posture.availability)"
                    + "  calibrated=\(posture.isCalibrated)"
                    + "  drop=\(drop)"
                    + "  showsPosture=\(self.state.showsPosture)"
                    + "  tabs=\(self.state.visibleTabs.map(\.rawValue).joined(separator: "/"))\n"
                if let handle = FileHandle(forWritingAtPath: path) {
                    handle.seekToEndOfFile()
                    handle.write(Data(line.utf8))
                    try? handle.close()
                } else {
                    try? line.write(toFile: path, atomically: true, encoding: .utf8)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Brings the shelf up without stealing the panel from someone mid-drag.
    private func revealShelf() {
        guard !state.interactionLocked else { return }
        state.tab = .shelf
        state.forceExpandUntil = Date().addingTimeInterval(4)
    }

    /// The screenshot folder is only watched while the shelf is on, so the app
    /// holds no handle on it otherwise.
    func updateShelfWatcher() {
        if state.prefs.shelfEnabled {
            screenshots.start()
        } else {
            screenshots.stop()
            state.shelf.clear()
        }
    }

    /// Head motion is only requested while posture alerts are on: streaming it
    /// costs AirPods battery, so it is not something to leave running by default.
    func updatePostureMonitor() {
        if state.prefs.postureAlerts {
            state.posture.enable()
        } else {
            state.posture.disable()
        }
    }

    /// Claude Code transcripts are only read once the feature is switched on.
    func updateClaudeMonitor() {
        if state.prefs.showClaudeUsage {
            state.claude.start()
        } else {
            state.claude.stop()
        }
    }

    // MARK: - Window

    private func rebuild() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let metrics = NotchGeometry.metrics(for: screen)
        state.metrics = metrics

        let frame = NSRect(
            x: metrics.screenFrame.midX - Layout.windowWidth / 2,
            y: metrics.screenFrame.maxY - Layout.windowHeight,
            width: Layout.windowWidth,
            height: Layout.windowHeight
        )

        if let panel {
            panel.setFrame(frame, display: true)
            applyWindowLevel()
            return
        }

        let panel = NotchPanel(contentRect: frame)
        let root = NotchRootView(state: state, music: state.music, pomodoro: state.pomodoro)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel
        applyWindowLevel()
    }

    /// Re-applies the window level after the lock screen preference changes.
    func applyWindowLevel() {
        panel?.applyLevel(showOnLockScreen: state.prefs.showOnLockScreen)
    }

    // MARK: - Hover

    private func tick() {
        guard state.metrics != nil else { return }

        state.expireActivityIfNeeded()

        if let until = state.forceExpandUntil {
            if until > Date() {
                setExpanded(true)
                return
            }
            state.forceExpandUntil = nil
        }

        let mouse = NSEvent.mouseLocation

        if state.isExpanded {
            // Don't collapse mid-drag or while a button is held down.
            guard !state.interactionLocked, NSEvent.pressedMouseButtons == 0 else { return }
            if !state.expandedHitRect.contains(mouse) {
                setExpanded(false)
            }
        } else if state.collapsedHitRect.contains(mouse) {
            setExpanded(true)
        }
    }

    func setExpanded(_ expanded: Bool) {
        guard state.isExpanded != expanded else { return }
        state.isExpanded = expanded
        // While collapsed the panel must let clicks through to the menu bar.
        panel?.ignoresMouseEvents = !expanded
        // Files on the shelf move and get deleted behind Islet's back; opening
        // the panel is the natural moment to notice.
        if expanded { state.shelf.prune() }
        state.music.isActive = expanded
        if expanded {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func open(tab: NotchState.Tab) {
        state.tab = tab
        state.forceExpandUntil = Date().addingTimeInterval(3)
    }
}
