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

    func start() {
        rebuild()
        state.music.start()
        startMonitors()

        // Documentation hook: ISLET_DEMO=music|timer holds the panel open on one
        // tab so screenshots for the README are reproducible. Deliberately time
        // limited — a panel stuck open forever is worse than a missed capture.
        if let demo = ProcessInfo.processInfo.environment["ISLET_DEMO"] {
            state.tab = demo.lowercased() == "timer" ? .timer : .music
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
        state.claude.start()
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
