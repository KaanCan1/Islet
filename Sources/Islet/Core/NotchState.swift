import AppKit
import Combine

@MainActor
final class NotchState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case music, timer
        var id: String { rawValue }
        var icon: String { self == .music ? "music.note" : "timer" }
        var height: CGFloat { self == .music ? Layout.musicHeight : Layout.timerHeight }
    }

    @Published var isExpanded = false
    @Published var tab: Tab = .music
    /// Keeps the panel open while a slider is being dragged, even if the cursor
    /// wanders outside it.
    @Published var interactionLocked = false
    /// Holds the panel open for a while after events like the timer finishing.
    @Published var forceExpandUntil: Date?
    /// A transient alert shown without any user interaction.
    @Published private(set) var activity: NotchActivity?
    private var activityExpiry: Date?

    let music = MusicManager()
    let pomodoro = PomodoroTimer()
    let prefs = Preferences.shared

    var metrics: NotchMetrics?
    private var bag = Set<AnyCancellable>()

    init() {
        // Changes in the child objects affect the peek width, so forward them up.
        for publisher in [music.objectWillChange, pomodoro.objectWillChange, prefs.objectWillChange] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        }
        // When the timer finishes, open the panel on the Timer tab.
        pomodoro.$finishedAt
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.tab = .timer
                self?.forceExpandUntil = Date().addingTimeInterval(6)
            }
            .store(in: &bag)
    }

    // MARK: - Transient alerts

    enum Presentation { case collapsed, activity, expanded }

    var presentation: Presentation {
        if isExpanded { return .expanded }
        return activity == nil ? .collapsed : .activity
    }

    func present(_ new: NotchActivity) {
        // Never interrupt someone who is using the panel.
        guard !isExpanded, prefs.showBatteryAlerts else { return }
        activity = new
        activityExpiry = Date().addingTimeInterval(new.duration)
    }

    /// Clears an expired alert; the controller calls this every frame.
    func expireActivityIfNeeded() {
        if isExpanded, activity != nil {
            activity = nil
            activityExpiry = nil
            return
        }
        guard let expiry = activityExpiry, expiry <= Date() else { return }
        activity = nil
        activityExpiry = nil
    }

    // MARK: - Sizes

    var notchSize: CGSize { metrics?.notchSize ?? CGSize(width: 190, height: 32) }

    var showsPeek: Bool {
        prefs.showPeek && (music.track.isPlaying || pomodoro.isRunning)
    }

    /// Width added either side of the notch while collapsed.
    var peekWidth: CGFloat { showsPeek ? Layout.peek : 0 }

    var collapsedSize: CGSize {
        CGSize(width: notchSize.width + peekWidth * 2 + Layout.shoulder * 2,
               height: notchSize.height)
    }

    var expandedSize: CGSize {
        // The top strip stays empty: the physical notch sits there, so anything
        // drawn in that band is simply not visible.
        CGSize(width: max(Layout.contentWidth, notchSize.width) + Layout.shoulder * 2,
               height: notchSize.height + tab.height)
    }

    var activitySize: CGSize {
        CGSize(width: max(activity?.contentWidth ?? 0, notchSize.width) + Layout.shoulder * 2,
               height: notchSize.height + Layout.activityHeight)
    }

    var frameSize: CGSize {
        switch presentation {
        case .expanded: return expandedSize
        case .activity: return activitySize
        case .collapsed: return collapsedSize
        }
    }

    /// Trace the playing track's progress around the notch while collapsed.
    var showsProgressRing: Bool {
        prefs.showProgressRing && !isExpanded && music.track.isPlaying && music.track.duration > 0
    }

    var musicProgress: Double {
        guard music.track.duration > 0 else { return 0 }
        return min(max(music.position / music.track.duration, 0), 1)
    }

    /// Fully transparent while collapsed and idle: nothing but the notch shows.
    var chromeOpacity: Double { presentation != .collapsed || showsPeek ? 1 : 0 }

    // MARK: - Hover regions (global coordinates)

    private func rect(size: CGSize, extraBottom: CGFloat) -> CGRect {
        guard let metrics else { return .zero }
        let frame = metrics.screenFrame
        return CGRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - extraBottom,
            width: size.width,
            height: size.height + extraBottom
        )
    }

    /// Collapsed: the notch itself plus a little slack below it, so the panel can
    /// be opened without shoving the cursor into the very top row of pixels
    /// (which is what makes macOS reveal the menu bar in full-screen apps).
    var collapsedHitRect: CGRect {
        let size = CGSize(width: notchSize.width + peekWidth * 2, height: notchSize.height)
        return rect(size: size, extraBottom: 8)
    }

    /// Expanded: the body, the tab bar under it, and slack around both.
    var expandedHitRect: CGRect {
        let size = CGSize(width: expandedSize.width + Layout.hoverSlack * 2,
                          height: expandedSize.height)
        return rect(size: size, extraBottom: Layout.tabBarGap + Layout.tabBarHeight + Layout.hoverSlack)
    }
}
