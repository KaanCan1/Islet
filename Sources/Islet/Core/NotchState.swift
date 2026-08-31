import AppKit
import Combine

@MainActor
final class NotchState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case music, timer, claude
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .music: return "music.note"
            case .timer: return "timer"
            case .claude: return "gauge.medium"
            }
        }

        var height: CGFloat {
            switch self {
            case .music: return Layout.musicHeight
            case .timer: return Layout.timerHeight
            case .claude: return Layout.claudeHeight
            }
        }
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
    let claude = ClaudeUsageMonitor()
    let prefs = Preferences.shared

    var metrics: NotchMetrics?
    private var bag = Set<AnyCancellable>()

    init() {
        // Changes in the child objects affect the peek width, so forward them up.
        for publisher in [music.objectWillChange, pomodoro.objectWillChange,
                          claude.objectWillChange, prefs.objectWillChange] {
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

    /// The Claude tab exists only when the feature is on and there is something
    /// to show. With no Claude Code sessions on the machine it disappears
    /// entirely, leaving music and timer.
    var showsClaude: Bool {
        prefs.showClaudeUsage && claude.snapshot != nil
    }

    var visibleTabs: [Tab] {
        showsClaude ? Tab.allCases : Tab.allCases.filter { $0 != .claude }
    }

    /// Falls back to music if the selected tab has just disappeared.
    var effectiveTab: Tab {
        visibleTabs.contains(tab) ? tab : .music
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
               height: notchSize.height + effectiveTab.height)
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
    ///
    /// Sized to the tallest tab rather than the current one. Switching from a tall
    /// tab to a short one otherwise leaves the cursor below the new hit rect —
    /// which collapses the panel the instant you click the tab you wanted.
    var expandedHitRect: CGRect {
        let tallest = Tab.allCases.map(\.height).max() ?? effectiveTab.height
        let size = CGSize(width: expandedSize.width + Layout.hoverSlack * 2,
                          height: notchSize.height + tallest)
        return rect(size: size, extraBottom: Layout.tabBarGap + Layout.tabBarHeight + Layout.hoverSlack)
    }
}
