import Foundation
import Testing
@testable import Islet

/// What the notch does when the pomodoro runs out: a short alert rather than
/// the whole panel, held back while the panel is in use.
@MainActor
@Suite struct TimerFinishTests {
    /// Starts the timer in `mode` and runs it out at once, the way it really
    /// ends — including the mode flipping to the next one straight after.
    private func finish(_ mode: PomodoroTimer.Mode, on state: NotchState) {
        let timer = state.pomodoro
        timer.chime = { _ in }
        timer.mode = mode
        timer.start()
        timer.tick(at: Date().addingTimeInterval(timer.remaining + 1))
    }

    @Test func aFinishedFocusSaysSoWithoutOpeningThePanel() {
        let state = NotchState()
        state.tab = .music
        finish(.focus, on: state)

        #expect(state.activity == .timer(finished: .focus, nextMinutes: state.pomodoro.breakMinutes))
        #expect(state.presentation == .activity)
        #expect(state.isExpanded == false)
        #expect(state.forceExpandUntil == nil)
        // Underneath, so hovering lands where the next one starts.
        #expect(state.tab == .timer)
    }

    @Test func aFinishedBreakPointsBackToWork() {
        let state = NotchState()
        finish(.breakTime, on: state)
        #expect(state.activity == .timer(finished: .breakTime, nextMinutes: state.pomodoro.focusMinutes))
    }

    @Test func theTimerHasMovedOnToWhatComesNext() {
        let state = NotchState()
        finish(.focus, on: state)
        #expect(state.pomodoro.mode == .breakTime)
        #expect(state.pomodoro.isRunning == false)
        #expect(state.pomodoro.finished?.mode == .focus)
    }

    @Test func theCaptionNamesWhatComesNext() {
        #expect(NotchActivity.timer(finished: .focus, nextMinutes: 5).caption == "focus done · 5 min break")
        #expect(NotchActivity.timer(finished: .breakTime, nextMinutes: 25).caption == "break over · 25 min focus")
    }

    @Test func anOpenPanelKeepsItsTabAndGetsTheAlertWhenItCloses() {
        let state = NotchState()
        state.tab = .music
        state.isExpanded = true
        finish(.focus, on: state)

        #expect(state.activity == nil)
        #expect(state.tab == .music)

        state.isExpanded = false
        #expect(state.activity == .timer(finished: .focus, nextMinutes: state.pomodoro.breakMinutes))
    }

    @Test func aHeldAlertIsDroppedOnceTheTimerIsStartedAgain() {
        let state = NotchState()
        state.isExpanded = true
        finish(.focus, on: state)

        // Started from the panel: the finish was plainly seen.
        state.pomodoro.start()
        defer { state.pomodoro.reset() }
        state.isExpanded = false
        #expect(state.activity == nil)
    }

    @Test func aHeldAlertIsDroppedOnceTheTimerIsReset() {
        let state = NotchState()
        state.isExpanded = true
        finish(.focus, on: state)

        state.pomodoro.reset()
        state.isExpanded = false
        #expect(state.activity == nil)
    }

    @Test func aHeldAlertIsShownOnce() {
        let state = NotchState()
        state.isExpanded = true
        finish(.focus, on: state)
        state.isExpanded = false
        #expect(state.activity != nil)

        state.isExpanded = true
        state.expireActivityIfNeeded()
        state.isExpanded = false
        #expect(state.activity == nil)
    }
}
