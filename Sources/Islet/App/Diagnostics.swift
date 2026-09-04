import AppKit

/// `Islet --diagnose` prints the screen and notch measurements, permission state
/// and the raw now-playing payload. Handy for multi-monitor setups and for
/// working out why a player isn't reporting anything.
enum Diagnostics {
    @MainActor
    static func run() {
        print("Islet diagnostics")
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("")

        for (index, screen) in NSScreen.screens.enumerated() {
            let metrics = NotchGeometry.metrics(for: screen)
            let isPreferred = screen == NotchGeometry.preferredScreen()
            print("[\(index)] \(screen.localizedName)\(isPreferred ? "  <- panel goes here" : "")")
            print("     frame        : \(fmt(screen.frame))")
            print("     safeArea.top : \(screen.safeAreaInsets.top)")
            print("     real notch   : \(metrics.isReal ? "yes" : "no (virtual notch)")")
            print("     notch size   : \(Int(metrics.notchSize.width)) x \(Int(metrics.notchSize.height))")
            print("     notch rect   : \(fmt(metrics.notchRect))")
            print("")
        }

        print("Players: Spotify \(PlayerApp.spotify.isRunning ? "running" : "not running"), "
              + "Music \(PlayerApp.music.isRunning ? "running" : "not running")")
        print("Accessibility (media keys): \(MediaKeys.isTrusted ? "granted" : "not granted")")

        if let snapshot = BatteryMonitor().probe() {
            print("Battery: \(snapshot.percent)%, "
                  + "\(snapshot.isCharging ? "charging" : (snapshot.isPlugged ? "plugged in" : "on battery"))"
                  + (snapshot.minutes > 0 ? ", \(snapshot.minutes) min" : ""))
        } else {
            print("Battery: no power source reported (desktop Mac?)")
        }

        let box = APIBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task { box.result = await ClaudeUsageAPI.fetch(); semaphore.signal() }
        while box.result == nil, semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        switch box.result {
        case .success(let reading):
            let five = reading.fiveHour.map { "\(Int($0.utilization * 100))%" } ?? "not reported"
            let seven = reading.sevenDay.map { "\(Int($0.utilization * 100))%" } ?? "not reported"
            print("Claude usage API: five_hour \(five), seven_day \(seven)")
        case .failure(let failure):
            print("Claude usage API: unavailable (\(failure)) — falling back to transcripts")
            print("  keychain: \(ClaudeUsageAPI.tokenStatus())")
            if let detail = ClaudeUsageAPI.lastRenewDetail {
                print("  renewal : \(detail)")
            }
        case nil:
            print("Claude usage API: timed out")
        }

        if let usage = ClaudeUsageMonitor.probe() {
            for (label, window) in [("5-hour block", usage.fiveHour), ("7 days      ", usage.sevenDay)] {
                let percent = window.percentText.map {
                    "\($0) \(window.isExact ? "(exact)" : "(estimated from \(window.ceilingText ?? "?"))")"
                } ?? "no percentage available"
                print("Claude \(label): \(percent), \(window.usageText) of use, "
                      + "\(window.tokensText) tokens, resets in \(window.remainingText)"
                      + (window.limitReached ? " — rate limited" : ""))
            }
        } else {
            print("Claude usage: no recent Claude Code sessions found")
        }

        // Debug hook: ISLET_SCRIPT runs any AppleScript under the app's own
        // identity, which is the quickest way to test player scripts.
        if let custom = ProcessInfo.processInfo.environment["ISLET_SCRIPT"] {
            print("")
            print("Custom script:")
            print(describe(runSync(custom)))
            return
        }

        for app in [PlayerApp.spotify, .music] where app.isRunning {
            print("")
            print("\(app.displayName) query:")
            switch runSync(MusicManager.nowPlayingScript(for: app)) {
            case .success(let raw):
                let fields = raw.components(separatedBy: "\t")
                let labels = ["title", "artist", "album", "length", "position", "state", "artwork", "shuffle", "repeat"]
                for (label, value) in zip(labels, fields) {
                    print("     \(label.padding(toLength: 9, withPad: " ", startingAt: 0)): \(value)")
                }
            case .failure(let failure):
                print("     error \(failure.code): \(failure.localizedHint)")
            case nil:
                print("     timed out (permission dialog left unanswered?)")
            }
        }
    }

    /// Runs a script and spins the run loop until the result lands, because the
    /// runner hands results back on the main queue.
    private static func runSync(_ source: String) -> Result<String, AppleScriptFailure>? {
        let box = ResultBox()
        AppleScriptRunner.shared.runDetailed(source) { box.value = $0 }
        let deadline = Date().addingTimeInterval(20)
        while box.value == nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return box.value
    }

    private static func describe(_ result: Result<String, AppleScriptFailure>?) -> String {
        switch result {
        case .success(let raw): return "     OK: " + raw
        case .failure(let failure): return "     error \(failure.code): \(failure.localizedHint)"
        case nil: return "     timed out"
        }
    }

    private final class APIBox {
        var result: Result<ClaudeUsageAPI.Reading, ClaudeUsageAPI.Failure>?
    }

    private final class ResultBox {
        var value: Result<String, AppleScriptFailure>?
    }

    private static func fmt(_ rect: CGRect) -> String {
        "(\(Int(rect.origin.x)), \(Int(rect.origin.y))) \(Int(rect.width)) x \(Int(rect.height))"
    }
}
