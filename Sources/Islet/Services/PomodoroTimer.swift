import AppKit

@MainActor
final class PomodoroTimer: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case focus, breakTime
        var id: String { rawValue }
        var title: String { self == .focus ? "Focus" : "Break" }
    }

    @Published var mode: Mode = .focus { didSet { if !isRunning { remaining = Double(minutes * 60) } } }
    /// Chosen length in minutes, kept separately per mode.
    @Published var focusMinutes: Int = Preferences.shared.focusMinutes {
        didSet {
            Preferences.shared.focusMinutes = focusMinutes
            if mode == .focus, !isRunning { remaining = Double(focusMinutes * 60) }
        }
    }
    @Published var breakMinutes: Int = Preferences.shared.breakMinutes {
        didSet {
            Preferences.shared.breakMinutes = breakMinutes
            if mode == .breakTime, !isRunning { remaining = Double(breakMinutes * 60) }
        }
    }
    @Published private(set) var remaining: Double = Double(Preferences.shared.focusMinutes * 60)
    @Published private(set) var isRunning = false
    /// Signal used to open the panel by itself when the timer runs out.
    @Published private(set) var finishedAt: Date?

    private var timer: Timer?
    private var deadline: Date?

    var minutes: Int {
        get { mode == .focus ? focusMinutes : breakMinutes }
        set { if mode == .focus { focusMinutes = newValue } else { breakMinutes = newValue } }
    }

    var total: Double { Double(minutes * 60) }
    var progress: Double { total > 0 ? 1 - (remaining / total) : 0 }

    var displayTime: String {
        let value = max(0, Int(remaining.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        if remaining <= 0 { remaining = total }
        deadline = Date().addingTimeInterval(remaining)
        isRunning = true
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        deadline = nil
    }

    func reset() {
        pause()
        remaining = total
        finishedAt = nil
    }

    private func onTick() {
        guard let deadline else { return }
        remaining = max(0, deadline.timeIntervalSinceNow)
        guard remaining <= 0 else { return }

        pause()
        finishedAt = Date()
        if Preferences.shared.chimeEnabled {
            NSSound(named: mode == .focus ? "Glass" : "Submarine")?.play()
        }
        // Focus rolls into a break and vice versa.
        mode = mode == .focus ? .breakTime : .focus
        remaining = total
    }
}
