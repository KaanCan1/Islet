import AppKit

// Backdrop plus a scripted cursor, so the demo recording shows the panel over a
// flat colour instead of whatever happens to be on screen. Covers only the strip
// being recorded, and goes away when the sequence ends.
//
// The backdrop is the cream the promo composition is built on, so the footage
// drops into the page without a recolour pass — a keyed background leaves a
// faint rectangle where the two creams disagree.

// The notch is the subject, so the stage belongs on the screen that has one.
// Asking for the main screen is not enough: with a second display attached it
// can be the one without a notch, and the whole sequence lands off-camera.
let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    ?? NSScreen.screens.first { $0.frame.origin == .zero }
    ?? NSScreen.main!
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
        backgroundColor = NSColor(srgbRed: 250 / 255, green: 249 / 255, blue: 245 / 255, alpha: 1)
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

/// Posted as a real move rather than warped. A warp relocates the cursor
/// without an event, and Islet follows the pointer by its events; a warped
/// glide is only noticed by its slow fallback poll, and the panel opens late.
func warp(_ x: CGFloat, _ y: CGFloat) {
    cursor = CGPoint(x: x, y: y)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: cursor, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func glide(to target: CGPoint, seconds: Double) {
    let start = cursor
    let begin = Date()
    // Driven off the clock rather than a fixed number of steps: a sleep that
    // overruns would otherwise stretch the move, and at 60fps that reads as a
    // stutter. Smoothstep so it starts and stops like a hand, not a ramp.
    while true {
        let t = min(1, Date().timeIntervalSince(begin) / seconds)
        let eased = t * t * (3 - 2 * t)
        warp(start.x + (target.x - start.x) * eased, start.y + (target.y - start.y) * eased)
        if t >= 1 { break }
        Thread.sleep(forTimeInterval: 1.0 / 120)   // the built-in display's rate
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

// `--rect` prints the screencapture region for this screen and exits, so the
// recorder and the stage cannot disagree about where the strip is.
if CommandLine.arguments.contains("--rect") {
    let width: CGFloat = 495, height: CGFloat = 215
    // screencapture counts from the top-left of the primary screen; NSScreen
    // counts from the bottom-left. Only the vertical axis disagrees.
    let top = (NSScreen.screens.first?.frame.maxY ?? full.maxY) - full.maxY
    print("\(Int(centreX - width / 2)),\(Int(top)),\(Int(width)),\(Int(height))")
    exit(0)
}

// `--preselect <tab>` opens the panel, clicks one tab, and leaves — no backdrop,
// no recording. The shelf reveals itself for a few seconds whenever a screenshot
// lands, which leaves its own tab selected; seeding the shelf before a take
// therefore decides which panel the take opens on. This puts that back.
if let index = CommandLine.arguments.firstIndex(of: "--preselect"),
   index + 1 < CommandLine.arguments.count {
    let target = CommandLine.arguments[index + 1]
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    DispatchQueue.global(qos: .userInteractive).async {
        warp(centreX, 240)
        hold(0.4)
        glide(to: CGPoint(x: centreX, y: notchHeight / 2), seconds: 0.5)
        hold(1.8)
        // Aimed with the shelf showing, which is what the reveal leaves open. The
        // tab is 24pt tall, so the few points of error from a different open tab
        // still land inside it.
        let point = tabCentre(target, showing: "shelf")
        glide(to: point, seconds: 0.4)
        click(point.x, point.y)
        hold(0.8)
        glide(to: CGPoint(x: centreX, y: 260), seconds: 0.5)
        hold(1.4)
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
    app.run()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let backdrop = Backdrop(backdropRect)
backdrop.orderFrontRegardless()

// The choreography runs off the main thread so the main thread can keep the
// run loop going. Sleeping on it instead left the backdrop window undrawn, and
// the recording showed the desktop through it.
DispatchQueue.global(qos: .userInteractive).async {
    let lead = Double(ProcessInfo.processInfo.environment["STAGE_LEAD"] ?? "1.4") ?? 1.4
    warp(centreX, 235)
    hold(lead)

    glide(to: CGPoint(x: centreX, y: notchHeight / 2), seconds: 0.75)  // into the notch: it opens
    hold(2.8)

    // Each click is aimed using the tab that is open at the time. The holds are
    // long enough that a viewer can finish reading the panel before it changes.
    var showing = "music"
    for next in ["shelf", "timer", "posture", "claude"] {
        let point = tabCentre(next, showing: showing)
        glide(to: point, seconds: 0.55)
        click(point.x, point.y)
        showing = next
        hold(2.5)
    }

    // A small summary stays beside the notch while something is playing, so with
    // music running the panel never actually collapses to nothing. Stopping
    // playback first is what makes the closing shot show an empty strip, which
    // is the thing the recording is here to prove.
    if ProcessInfo.processInfo.environment["STAGE_PAUSE_MUSIC"] == "1" {
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        script.arguments = ["-e", "tell application \"Music\" to if it is running then pause"]
        try? script.run()
        script.waitUntilExit()
        hold(1.2)
    }

    glide(to: CGPoint(x: centreX, y: 245), seconds: 1.0)  // away: the panel closes
    hold(2.4)

    DispatchQueue.main.async {
        backdrop.orderOut(nil)
        NSApp.terminate(nil)
    }
}

app.run()
