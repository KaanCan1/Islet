import SwiftUI

struct TimerPanel: View {
    @ObservedObject var pomodoro: PomodoroTimer
    @ObservedObject var state: NotchState

    private var tint: Color { pomodoro.mode == .focus ? .orange : .cyan }

    var body: some View {
        VStack(spacing: 7) {
            SegmentedPill(
                options: [(PomodoroTimer.Mode.focus, "Focus"), (PomodoroTimer.Mode.breakTime, "Break")],
                selection: Binding(get: { pomodoro.mode }, set: { pomodoro.mode = $0 }),
                tint: tint
            )

            RulerSlider(
                value: Binding(get: { pomodoro.minutes }, set: { pomodoro.minutes = $0 }),
                tint: tint,
                onEditingChanged: { state.interactionLocked = $0 }
            )
            .opacity(pomodoro.isRunning ? 0.35 : 1)
            .disabled(pomodoro.isRunning)

            HStack(spacing: 8) {
                Button(action: { pomodoro.toggle() }) {
                    Text(pomodoro.isRunning ? "Pause" : "Start Timer")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .frame(width: 100, height: 28)
                        .background(Capsule().fill(tint.opacity(0.16)))
                        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.8))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                IconButton(
                    symbol: state.prefs.chimeEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    size: 11,
                    tint: tint,
                    isOn: state.prefs.chimeEnabled
                ) { state.prefs.chimeEnabled.toggle() }

                IconButton(symbol: "arrow.counterclockwise", size: 11, tint: .white) { pomodoro.reset() }

                Spacer(minLength: 0)

                Text(pomodoro.displayTime)
                    .font(.system(size: 25, weight: .medium, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: pomodoro.displayTime)
            }
            .frame(height: 30)
        }
        .padding(.horizontal, 13)
        .padding(.top, 3)
        .padding(.bottom, 9)
    }
}
