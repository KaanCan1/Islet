import AppKit
import Combine

@MainActor
final class NotchState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case music, shelf, timer, posture, claude
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .music: return "music.note"
            case .shelf: return "photo.on.rectangle.angled"
            case .timer: return "timer"
            case .posture: return "figure.seated.side"
            case .claude: return "gauge.medium"
            }
        }

        var height: CGFloat {
            switch self {
            case .music: return Layout.musicHeight
            case .shelf: return Layout.shelfHeight
            case .timer: return Layout.timerHeight
            case .posture: return Layout.postureHeight
            case .claude: return Layout.claudeHeight
            }
        }
    }

    @Published var isExpanded = false {
        didSet { if !isExpanded { presentHeld() } }
    }
    @Published var tab: Tab = .music
    /// Keeps the panel open while a slider is being dragged, even if the cursor
    /// wanders outside it.
    @Published var interactionLocked = false
    /// Holds the panel open for a while after events like the timer finishing.
    @Published var forceExpandUntil: Date?
    /// A transient alert shown without any user interaction.
    @Published private(set) var activity: NotchActivity?
    private var activityExpiry: Date?
    /// An alert that arrived while the panel was in use, kept for when it
    /// closes, and whether it still means anything by then.
    private var held: (activity: NotchActivity, stillWanted: () -> Bool)?

    let music = MusicManager()
    let pomodoro = PomodoroTimer()
    let claude = ClaudeUsageMonitor()
    let shelf = ShelfStore()
    let posture = PostureMonitor()
    let prefs = Preferences.shared

    var metrics: NotchMetrics?
    private var bag = Set<AnyCancellable>()

    init() {
        // Changes in the child objects affect the peek width, so forward them up.
        for publisher in [music.objectWillChange, pomodoro.objectWillChange,
                          claude.objectWillChange, shelf.objectWillChange,
                          posture.objectWillChange, prefs.objectWillChange] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        }
        pomodoro.$finished
            .compactMap { $0 }
            .sink { [weak self] finish in self?.timerFinished(finish) }
            .store(in: &bag)
    }

    /// The Claude tab exists only when the feature is on and there is something
    /// to show. With no Claude Code sessions on the machine it disappears
    /// entirely, leaving music and timer.
    var showsClaude: Bool {
        prefs.showClaudeUsage && claude.snapshot != nil
    }

    /// The shelf appears when it is holding something and goes away when the last
    /// screenshot is taken off it, so the tab bar stays empty until it earns a slot.
    var showsShelf: Bool {
        prefs.shelfEnabled && !shelf.isEmpty
    }

    /// Posture needs AirPods that report head motion; without them there is
    /// nothing to show and the tab never appears. Waiting counts as something to
    /// show: the panel is where it explains that they are connected but idle.
    var showsPosture: Bool {
        guard prefs.postureAlerts else { return false }
        return posture.availability == .tracking || posture.availability == .waiting
    }

    var visibleTabs: [Tab] {
        Tab.allCases.filter { tab in
            switch tab {
            case .shelf: return showsShelf
            case .posture: return showsPosture
            case .claude: return showsClaude
            case .music, .timer: return true
            }
        }
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

    /// Returns whether the alert was actually put on screen. Callers that pay
    /// for one — posture spends a budget and starts a quiet period — need to
    /// know, or an alert refused here is simply lost.
    @discardableResult
    func present(_ new: NotchActivity) -> Bool {
        // Never interrupt someone who is using the panel.
        guard !isExpanded, new.isEnabled else { return false }
        activity = new
        activityExpiry = Date().addingTimeInterval(new.duration)
        return true
    }

    /// The timer running out is said beside the notch rather than by throwing
    /// the whole panel open: a finished block is news, not a reason to cover
    /// whatever you were looking at. The Timer tab is put up underneath, so
    /// hovering lands where the next one starts.
    ///
    /// With the panel in use the tab is left alone — switching it under the
    /// cursor is worse than the panel opening by itself was — and the alert
    /// waits for the panel to close, unless the timer has been started or
    /// reset by then, which says it was seen.
    func timerFinished(_ finish: PomodoroTimer.Finish) {
        let next = finish.mode == .focus ? pomodoro.breakMinutes : pomodoro.focusMinutes
        let alert = NotchActivity.timer(finished: finish.mode, nextMinutes: next)
        guard isExpanded else {
            tab = .timer
            present(alert)
            return
        }
        held = (alert, { [weak self] in
            guard let self else { return false }
            return !self.pomodoro.isRunning && self.pomodoro.finished == finish
        })
    }

    private func presentHeld() {
        guard let held else { return }
        self.held = nil
        if held.stillWanted() { present(held.activity) }
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
        let tallest = visibleTabs.map(\.height).max() ?? effectiveTab.height
        let size = CGSize(width: expandedSize.width + Layout.hoverSlack * 2,
                          height: notchSize.height + tallest)
        return rect(size: size, extraBottom: Layout.tabBarGap + Layout.tabBarHeight + Layout.hoverSlack)
    }
}
