import AppKit
import CoreMotion

/// `Islet --posture` watches the headphone motion stream for a few seconds and
/// says exactly what it gets back.
///
/// Worth its own mode because everything about this feature fails silently: the
/// permission prompt, the connection and the sample stream all just produce
/// nothing when they go wrong, and the panel cannot tell you which one it was.
enum PostureProbe {
    /// Collected rather than printed as it goes: launched through LaunchServices
    /// — which is the only way to reproduce how the app itself starts — there is
    /// no terminal to print to, so `ISLET_PROBE_OUT` names a file instead.
    private static var lines: [String] = []

    private static func say(_ text: String) {
        lines.append(text)
        print(text)
    }

    private static func flush() {
        guard let path = ProcessInfo.processInfo.environment["ISLET_PROBE_OUT"], !path.isEmpty
        else { return }
        try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    @MainActor
    static func run(seconds: TimeInterval = 12) {
        // CoreMotion talks to a daemon, which needs an application to attribute
        // the request to. Without this the answer means nothing.
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.activate(ignoringOtherApps: true)

        // Drives PostureMonitor rather than CoreMotion directly: the raw stream
        // was never the doubtful part, the reference angle and the arithmetic
        // built on top of it were.
        // The real NotchState, not a lone monitor: "no alerts" can just as easily
        // mean the tab never qualified to appear, and that decision lives here.
        let state = NotchState()
        let monitor = state.posture
        say("Islet posture probe")
        say("authorization : \(PostureMonitor.authorizationText)")
        say("supported     : \(monitor.isSupported ? "yes" : "no headphones with motion sensors")")
        say("calibrated    : \(monitor.isCalibrated ? "yes, from a previous run" : "no, will settle on its own")")
        say("active app    : \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown")")

        // Only one process at a time is fed headphone motion, and the loser is
        // fed silence rather than an error. Without this the probe blames the
        // AirPods for a stream the app next door is already holding.
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != mine }
        if !others.isEmpty {
            say("")
            say("WARNING: Islet is already running (pid \(others.map { String($0.processIdentifier) }.joined(separator: ", "))).")
            say("Only one process receives head motion, so this probe will see nothing")
            say("while that one holds it. Quit Islet first, or watch the running app")
            say("itself with ISLET_STATE_LOG.")
        }
        say("watching for \(Int(seconds))s ...")
        say("")
        flush()

        monitor.onSlouch = { minutes in say("  ALERT after \(minutes) min") }
        monitor.enable()

        // The alert path, without waiting out the hold: if a slouch this long
        // cannot raise an activity, no amount of sitting badly ever will.
        state.present(.posture(degrees: 22, minutes: 3))
        say("alert plumbing: \(state.activity == nil ? "BLOCKED - nothing would show" : "ok, activity raised")")
        state.expireActivityIfNeeded()
        say("")
        flush()

        let deadline = Date().addingTimeInterval(seconds)
        var nextReport = Date()
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
            guard Date() >= nextReport else { continue }
            nextReport = Date().addingTimeInterval(2)
            let drop = monitor.drop.map { String(format: "%+.1f°", $0) } ?? "—"
            say("  \(pad(String(describing: monitor.availability)))"
                + " calibrated=\(monitor.isCalibrated ? "yes" : "no ")"
                + "  drop=\(pad(drop, 7))"
                + "  budget=\(pad(String(format: "%.0f%%", monitor.budgetFraction * 100), 5))"
                + "  tab=\(state.showsPosture ? "shown" : "HIDDEN")"
                + "  \(monitor.isSlouching ? "SLOUCHING" : "upright")")
        }
        // Read before disabling: stopping clears the live value, and reporting
        // "never produced a reading" after a screen full of them is worse than
        // saying nothing.
        let lastDrop = monitor.drop
        // Both read before disabling, which tears the tracking state back down.
        let tabs = state.visibleTabs.map(\.rawValue).joined(separator: ", ")
        monitor.disable()

        say("")
        say("worn today    : \(monitor.wornText)")
        say("head down     : \(monitor.slouchedText)")
        say("upright angle : \(String(format: "%.1f°", Preferences.shared.uprightPitch * 180 / .pi)) "
            + "(\(Preferences.shared.postureCalibrated ? "stored" : "not stored"))")
        say("alerts pref   : \(Preferences.shared.postureAlerts ? "on" : "OFF - nothing will ever fire")")
        say("visible tabs  : \(tabs)")
        say("nudge rule    : \(Int(PostureMonitor.budgetSeconds))s past "
            + "\(Int(PostureMonitor.thresholdDegrees))° within any "
            + "\(Int(PostureMonitor.windowSeconds / 60)) min, then "
            + "\(Int(PostureMonitor.cooldownSeconds / 60)) min quiet")

        if lastDrop == nil {
            say("")
            say("Never produced a reading. In order of likelihood: another Islet is")
            say("running and holding the stream, the AirPods are not in your ears, no")
            say("headphones with motion sensors are connected, or motion is refused.")
        }
        flush()
    }

    private static func pad(_ text: String, _ width: Int = 10) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }


}
