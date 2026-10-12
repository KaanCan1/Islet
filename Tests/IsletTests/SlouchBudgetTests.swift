import Foundation
import Testing
@testable import Islet

/// The posture nudge rule: 90 seconds down within any three minutes, then ten
/// minutes of quiet, run against a clock rather than a pair of AirPods.
@Suite struct SlouchBudgetTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// Feeds one-second readings for `seconds`, starting `at` seconds after
    /// `start`. Returns when the first nudge came due, in seconds after
    /// `start`, if one did.
    @discardableResult
    private func feed(_ budget: inout SlouchBudget, at offset: Double, for seconds: Int,
                      down: Bool) -> Double? {
        var due: Double?
        for second in 1 ... seconds {
            let now = offset + Double(second)
            if budget.record(isDown: down, seconds: 1, at: start + now) != nil, due == nil {
                due = now
            }
        }
        return due
    }

    @Test func anUnbrokenRunEarnsANudgeAtNinetySeconds() {
        var budget = SlouchBudget()
        #expect(feed(&budget, at: 0, for: 120, down: true) == 90)
    }

    @Test func glancingDownIsNotEnough() {
        var budget = SlouchBudget()
        #expect(feed(&budget, at: 0, for: 89, down: true) == nil)
        #expect(budget.fraction > 0.98 && budget.fraction < 1)
    }

    @Test func timeDownAddsUpAcrossTheWindow() {
        // Over the line and back, every few seconds: the way it goes at a desk,
        // and what a rule demanding one unbroken run never noticed.
        var budget = SlouchBudget()
        var due: Double?
        for cycle in 0 ..< 60 where due == nil {
            let at = Double(cycle * 6)
            due = feed(&budget, at: at, for: 3, down: true)
                ?? feed(&budget, at: at + 3, for: 3, down: false)
        }
        #expect(due == 177)
    }

    @Test func timeOlderThanTheWindowStopsCounting() {
        var budget = SlouchBudget()
        feed(&budget, at: 0, for: 60, down: true)
        feed(&budget, at: 60, for: 200, down: false)
        #expect(feed(&budget, at: 260, for: 60, down: true) == nil)
        #expect(budget.downSeconds == 60)
    }

    @Test func aNudgeThatWasNotShownStaysDue() {
        // The panel was open, say. Not spending it is the whole point: the
        // alternative is a nudge lost and the next ten minutes away.
        var budget = SlouchBudget()
        #expect(feed(&budget, at: 0, for: 90, down: true) == 90)
        #expect(budget.record(isDown: true, seconds: 1, at: start + 91) != nil)
        #expect(budget.record(isDown: false, seconds: 1, at: start + 92) != nil)
    }

    @Test func aShownNudgeIsFollowedByTenQuietMinutes() {
        var budget = SlouchBudget()
        feed(&budget, at: 0, for: 90, down: true)
        budget.spend(at: start + 90)

        #expect(feed(&budget, at: 90, for: 600, down: true) == 690)
    }

    @Test func theNextNudgeIsEarnedFromScratch() {
        var budget = SlouchBudget()
        feed(&budget, at: 0, for: 90, down: true)
        budget.spend(at: start + 90)
        // Sat up through the quiet period, then down again: ninety more seconds,
        // not a nudge the moment the quiet ends.
        feed(&budget, at: 90, for: 600, down: false)
        #expect(feed(&budget, at: 690, for: 120, down: true) == 780)
    }

    @Test func forgettingReadingsKeepsTheQuietPeriod() {
        var budget = SlouchBudget()
        feed(&budget, at: 0, for: 90, down: true)
        budget.spend(at: start + 90)
        budget.forgetReadings()

        #expect(feed(&budget, at: 90, for: 600, down: true) == 690)
    }

    @Test func forgettingReadingsStartsTheCountAgain() {
        var budget = SlouchBudget()
        feed(&budget, at: 0, for: 80, down: true)
        budget.forgetReadings()
        #expect(budget.fraction == 0)
        #expect(feed(&budget, at: 80, for: 89, down: true) == nil)
    }
}
