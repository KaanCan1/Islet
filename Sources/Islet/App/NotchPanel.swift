import AppKit

/// Transparent panel that sits above the menu bar and never takes focus.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        applyLevel(showOnLockScreen: false)
    }

    /// Normally sits just above the menu bar (level 24). To stay visible on the
    /// lock screen it goes above the shielding window, which is the level the
    /// screen saver and the lock curtain are drawn at.
    func applyLevel(showOnLockScreen: Bool) {
        let raw = showOnLockScreen
            ? Int(CGShieldingWindowLevel()) + 1
            : Int(CGWindowLevelForKey(.statusWindow)) + 1
        level = NSWindow.Level(rawValue: raw)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
