import AppKit

// Backdrop plus a scripted cursor, so the demo recording shows the panel over a
// flat colour instead of whatever happens to be on screen. Covers only the strip
// being recorded, and goes away when the sequence ends.

let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main!
let full = screen.frame                       // bottom-left origin
let centreX = full.midX

// Mirrors Layout.swift. The tab bar sits under the body, so its height moves
// with whichever tab is showing, and a click has to aim at the layout that is
// on screen when it lands — not the one it is about to produce.
let notchHeight = max(screen.safeAreaInsets.top, 32)
let tabBarGap: CGFloat = 7, tabBarHeight: CGFloat = 24
let tabWidth: CGFloat = 29, tabSpacing: CGFloat = 2, tabPadding: CGFloat = 3
let bodyHeights: [String: CGFloat] = ["music": 100, "shelf": 108, "timer": 108,
                                      "posture": 102, "claude": 138]
let order = ["music", "shelf", "timer", "posture", "claude"]

/// Centre of a tab button while `showing` is the open tab.
func tabCentre(_ name: String, showing: String) -> CGPoint {
    let count = CGFloat(order.count)
    let barWidth = count * tabWidth + (count - 1) * tabSpacing + tabPadding * 2
    let first = centreX - barWidth / 2 + tabPadding + tabWidth / 2
    let index = CGFloat(order.firstIndex(of: name) ?? 0)
    let y = notchHeight + (bodyHeights[showing] ?? 100) + tabBarGap + tabBarHeight / 2
    return CGPoint(x: first + index * (tabWidth + tabSpacing), y: y)
}

let backdropRect = NSRect(x: centreX - 286, y: full.maxY - 250, width: 572, height: 250)

final class Backdrop: NSPanel {
    init(_ rect: NSRect) {
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = NSColor(calibratedWhite: 0.949, alpha: 1)   // the grey the old demo used
        hasShadow = false
        // Absorbs clicks rather than passing them through: a coordinate that
        // misses the tab bar would otherwise land in whatever app is underneath.
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Under Islet's panel, over everything else.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
    }
}

/// Top-left origin, which is what every coordinate below is written in.
/// Tracked rather than read back, because the choreography runs off the main
/// thread and NSEvent.mouseLocation is not the place to ask from there.
var cursor = CGPoint(x: centreX, y: 235)

func warp(_ x: CGFloat, _ y: CGFloat) {
    cursor = CGPoint(x: x, y: y)
    CGWarpMouseCursorPosition(cursor)
}

func glide(to target: CGPoint, seconds: Double) {
    let steps = max(2, Int(seconds * 60))
    let start = cursor
    for step in 1...steps {
        // Ease in and out, so it reads as a hand rather than a teleport.
        let t = Double(step) / Double(steps)
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        warp(start.x + (target.x - start.x) * eased, start.y + (target.y - start.y) * eased)
        Thread.sleep(forTimeInterval: seconds / Double(steps))
    }
}

func click(_ x: CGFloat, _ y: CGFloat) {
    let point = CGPoint(x: x, y: y)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.04)
    }
}

func hold(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let backdrop = Backdrop(backdropRect)
backdrop.orderFrontRegardless()

// The choreography runs off the main thread so the main thread can keep the
// run loop going. Sleeping on it instead left the backdrop window undrawn, and
// the recording showed the desktop through it.
DispatchQueue.global(qos: .userInteractive).async {
    let lead = Double(ProcessInfo.processInfo.environment["STAGE_LEAD"] ?? "1.2") ?? 1.2
    warp(centreX, 235)
    hold(lead)

    glide(to: CGPoint(x: centreX, y: notchHeight / 2), seconds: 0.8)   // into the notch: it opens
    hold(2.6)

    // Each click is aimed using the tab that is open at the time.
    var showing = "music"
    for next in ["shelf", "timer", "posture", "claude"] {
        let point = tabCentre(next, showing: showing)
        glide(to: point, seconds: 0.45)
        click(point.x, point.y)
        showing = next
        hold(2.2)
    }

    glide(to: CGPoint(x: centreX, y: 245), seconds: 0.9)  // away: the panel closes
    hold(1.6)

    DispatchQueue.main.async {
        backdrop.orderOut(nil)
        NSApp.terminate(nil)
    }
}

app.run()
