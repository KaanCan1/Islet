import Testing
@testable import Islet

/// The rule behind the notch's Claude alerts, without preferences or a screen.
@Suite struct ClaudeAlertsTests {
    /// An exact reading, as the usage endpoint gives one.
    private func exact(_ fraction: Double, limit: Bool = false) -> ClaudeWindow {
        ClaudeWindow(usageSeconds: 0, tokens: 0, ceilingTokens: nil, resetsAt: nil,
                     limitReached: limit, exactPercent: fraction)
    }

    /// A local estimate: tokens against a learned ceiling of 1000.
    private func estimate(_ fraction: Double?, limit: Bool = false) -> ClaudeWindow {
        ClaudeWindow(usageSeconds: 0, tokens: Int((fraction ?? 0) * 1000),
                     ceilingTokens: fraction == nil ? nil : 1000, resetsAt: nil,
                     limitReached: limit)
    }

    private func decide(_ said: ClaudeAlerts.Level, _ window: ClaudeWindow) -> ClaudeAlerts.Decision {
        ClaudeAlerts.decide(said: said, window: window)
    }

    @Test func quietBelowTheFirstThreshold() {
        #expect(decide(.none, exact(0.42)) == .stay)
        #expect(decide(.none, exact(0.79)) == .stay)
    }

    @Test func roundsTheWayThePanelDoes() {
        // The panel shows 79.5% as 80%, so the alert must agree with it.
        #expect(decide(.none, exact(0.795)) == .announce(.warning))
    }

    @Test func saysEachLevelOnce() {
        #expect(decide(.warning, exact(0.88)) == .stay)
        #expect(decide(.warning, exact(0.95)) == .announce(.critical))
        #expect(decide(.critical, exact(0.99)) == .stay)
    }

    @Test func aJumpPastBothThresholdsSaysOnlyTheHigher() {
        #expect(decide(.none, exact(0.97)) == .announce(.critical))
    }

    @Test func fullWithoutACutOffIsNotTheLimit() {
        #expect(decide(.critical, exact(1.0)) == .stay)
    }

    @Test func aCutOffIsTheLimit() {
        #expect(decide(.critical, exact(1.0, limit: true)) == .announce(.limit))
        #expect(decide(.limit, exact(1.0, limit: true)) == .stay)
    }

    @Test func theLimitNeedsNoPercentage() {
        #expect(decide(.none, estimate(nil, limit: true)) == .announce(.limit))
    }

    @Test func stillLimitedWhileTheRejectionStands() {
        // Usage reads low the moment a new window opens, but a standing
        // rejection means it has not opened yet.
        #expect(decide(.limit, exact(0.02, limit: true)) == .stay)
    }

    @Test func aWindowWarnedAboutLoudlyComesClear() {
        #expect(decide(.limit, exact(0.02)) == .cleared)
        #expect(decide(.critical, exact(0.10)) == .cleared)
    }

    @Test func aWindowThatOnlyReachedAWarningTurnsOverQuietly() {
        #expect(decide(.warning, exact(0.10)) == .rearm)
    }

    @Test func aDipIsNotANewWindow() {
        #expect(decide(.warning, exact(0.60)) == .stay)
    }

    @Test func nothingToSayWithoutACeiling() {
        #expect(decide(.none, estimate(nil)) == .stay)
        #expect(decide(.warning, estimate(nil)) == .stay)
    }

    @Test func estimatesCountToo() {
        #expect(decide(.none, estimate(0.85)) == .announce(.warning))
    }
}
