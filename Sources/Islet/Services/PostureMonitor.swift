import AppKit
import CoreMotion
import Foundation

/// Reads the head angle from AirPods and says when it has been tilted down for a
/// long stretch.
///
/// What this measures is neck flexion — how far your head is tipped forward of
/// where you put it when you calibrated — not posture in any clinical sense. A
/// rounded back with a level head reads as fine here, and it is not medical
/// advice. It is a nudge, and it is deliberately slow to fire: glancing at the
/// keyboard is not slouching, so the angle has to hold for minutes.
///
/// Needs AirPods with motion sensors (Pro, 3rd gen, Max) and the one-time motion
/// permission. Everything stays on the device; nothing is recorded but a running
/// total for the current day.
@MainActor
final class PostureMonitor: NSObject, ObservableObject {
    enum Availability: Equatable {
        /// No headphones connected, or they have no motion sensors.
        case unavailable
        /// The motion permission was refused.
        case denied
        /// The stream is open but nothing is coming through. AirPods report
        /// motion only while they are being worn, so this is what "connected and
        /// sitting on the desk" looks like — and it has to be said out loud,
        /// because a panel that shows a confident 0° while receiving nothing is
        /// indistinguishable from one that is working.
        case waiting
        /// Samples are arriving.
        case tracking
    }

    /// How far below upright counts as slouching.
    static let thresholdDegrees: Double = 18

    @Published private(set) var availability: Availability = .unavailable
    /// False until a reference angle exists. Nothing is judged before then.
    @Published private(set) var isCalibrated = false
    /// Degrees below the calibrated upright angle; positive means head down.
    @Published private(set) var drop: Double?
    @Published private(set) var isSlouching = false
    @Published private(set) var wornSeconds: TimeInterval = 0
    @Published private(set) var slouchedSeconds: TimeInterval = 0

    /// Fires with the number of minutes spent down. Returns whether the nudge
    /// reached the screen: one that did not must not spend the budget or start
    /// the quiet period, or it is lost and the next is ten minutes away.
    var onSlouch: ((Int) -> Bool)?

    private let manager = CMHeadphoneMotionManager()
    private let prefs = Preferences.shared

    private var budget = SlouchBudget()
    private var lastSample: Date?
    private var statsDay: Date = Calendar.current.startOfDay(for: Date())
    private var lastPersist: Date?
    /// AirPods come and go. While the feature is on but nothing is connected,
    /// this keeps looking rather than making you toggle the menu item again.
    private var retry: Timer?
    /// Thins the stream before it reaches the main thread. Samples arrive at
    /// about 25 Hz and nothing here needs more than a couple a second, so the
    /// rest are dropped where they land instead of each waking the app.
    private let thinning = Thinning()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.islet.head-motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
    /// Why the stream is off although the feature is on. Sending head motion
    /// costs AirPods battery, and with the screen locked or asleep there is
    /// nobody at it to nudge, so it is stopped until there is.
    private var pausedFor: Set<Pause> = []
    private enum Pause { case locked, asleep }
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// First readings after starting, used to settle on an upright angle without
    /// making anyone press a button to get a working feature.
    private var calibrationSamples: [Double] = []
    private static let calibrationCount = 12

    override init() {
        super.init()
        manager.delegate = self
        isCalibrated = prefs.postureCalibrated
        restoreTotals()
        watchTheScreen()
    }

    /// Locking and display sleep come from different places: the lock is a
    /// distributed notification, the display from the workspace. Both are
    /// watched always — they cost nothing — and only matter while enabled.
    private func watchTheScreen() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        let watches: [(NotificationCenter, Notification.Name, Pause, Bool)] = [
            (distributed, Notification.Name("com.apple.screenIsLocked"), .locked, true),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), .locked, false),
            (workspace, NSWorkspace.screensDidSleepNotification, .asleep, true),
            (workspace, NSWorkspace.screensDidWakeNotification, .asleep, false)
        ]
        for (center, name, reason, starts) in watches {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause(reason, starts) }
            }
            observers.append((center, token))
        }
    }

    private func pause(_ reason: Pause, _ starts: Bool) {
        let wasPaused = !pausedFor.isEmpty
        if starts { pausedFor.insert(reason) } else { pausedFor.remove(reason) }
        guard retry != nil, wasPaused != !pausedFor.isEmpty else { return }

        if pausedFor.isEmpty {
            attach()
        } else {
            manager.stopDeviceMotionUpdates()
            // The gap is not time worn: the next sample starts the clock again.
            lastSample = nil
            drop = nil
            if availability == .tracking { availability = .waiting }
        }
    }

    /// The panel says "today", so the totals have to mean the day rather than
    /// the run. Anything stored under an earlier day is left behind.
    private func restoreTotals() {
        let stored = Date(timeIntervalSince1970: prefs.postureStatsDay)
        guard Calendar.current.isDate(stored, inSameDayAs: statsDay) else { return }
        wornSeconds = prefs.postureWornSeconds
        slouchedSeconds = prefs.postureSlouchedSeconds
    }

    /// Written at most every half minute: the totals move with every sample,
    /// and none of them is worth a trip to disk on its own.
    private func persistTotals(_ now: Date = Date(), force: Bool = false) {
        if !force, let last = lastPersist, now.timeIntervalSince(last) < 30 { return }
        lastPersist = now
        prefs.postureStatsDay = statsDay.timeIntervalSince1970
        prefs.postureWornSeconds = wornSeconds
        prefs.postureSlouchedSeconds = slouchedSeconds
    }

    // MARK: - Lifecycle

    /// Whether headphones that report head motion are connected right now.
    var isSupported: Bool { manager.isDeviceMotionAvailable }

    nonisolated static var authorizationText: String {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .authorized: return "granted"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not asked yet"
        @unknown default: return "unknown"
        }
    }

    func enable() {
        attach()
        guard retry == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Samples stopped without the headphones disconnecting: they are
                // out of your ears, which is not the same as tracking you.
                if self.availability == .tracking,
                   let last = self.lastSample, Date().timeIntervalSince(last) > 6 {
                    self.availability = .waiting
                    self.drop = nil
                }
                guard self.availability != .tracking else { return }
                self.attach()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retry = timer
    }

    func disable() {
        retry?.invalidate()
        retry = nil
        persistTotals(force: true)
        stop()
    }

    private func attach() {
        // Already streaming: leave it be. What the panel says about it is
        // decided by whether samples arrive, so a reconnect recovers on its own.
        guard !manager.isDeviceMotionActive else { return }
        // Paused for the screen: the retry timer must not undo that.
        guard pausedFor.isEmpty else { return }

        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            availability = .denied
            return
        default:
            break
        }

        guard manager.isDeviceMotionAvailable else {
            availability = .unavailable
            return
        }

        // Optimism ends here: .tracking is earned by an actual sample, in
        // consume(), not by the call that opens the stream succeeding.
        availability = .waiting
        thinning.reset()
        let thinning = self.thinning
        manager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            if error != nil {
                let denied = CMHeadphoneMotionManager.authorizationStatus() == .denied
                Task { @MainActor in self?.availability = denied ? .denied : .unavailable }
                return
            }
            // Only the pitch crosses over, and only a couple of times a second.
            guard let motion, thinning.admits(at: motion.timestamp) else { return }
            let pitch = motion.attitude.pitch
            Task { @MainActor in self?.consume(pitch: pitch) }
        }
    }

    private func stop() {
        manager.stopDeviceMotionUpdates()
        availability = .unavailable
        drop = nil
        isSlouching = false
        budget.forgetReadings()
        lastSample = nil
        calibrationSamples = []
    }

    /// Records the current angle as sitting upright. Everything is measured
    /// against this, because the sensor's own zero depends on how the AirPods
    /// happen to sit in your ears.
    func calibrate() {
        guard let motion = manager.deviceMotion else { return }
        setUpright(motion.attitude.pitch)
    }

    private func setUpright(_ pitch: Double) {
        prefs.uprightPitch = pitch
        prefs.postureCalibrated = true
        isCalibrated = true
        calibrationSamples = []
        drop = 0
        isSlouching = false
        budget.forgetReadings()
    }

    // MARK: - Sampling

    private func consume(pitch: Double) {
        let now = Date()

        if availability != .tracking { availability = .tracking }
        rolloverIfNeeded(now)

        // No reference angle yet: gather a few seconds and take the middle of
        // them, so the feature works on its own. Whatever you are doing then
        // becomes "upright", which is why the panel keeps offering to redo it.
        guard isCalibrated else {
            calibrationSamples.append(pitch)
            guard calibrationSamples.count >= Self.calibrationCount else { return }
            setUpright(calibrationSamples.sorted()[calibrationSamples.count / 2])
            return
        }

        // Positive = tipped forward of the calibrated upright angle.
        let degrees = (prefs.uprightPitch - pitch) * 180 / .pi
        drop = degrees

        // Time only accrues between nearby samples. A gap means the AirPods were
        // out or the Mac was asleep, and that is not time spent sitting badly.
        if let last = lastSample {
            let elapsed = now.timeIntervalSince(last)
            if elapsed <= 2 {
                wornSeconds += elapsed
                if degrees >= Self.thresholdDegrees { slouchedSeconds += elapsed }
                persistTotals(now)
                updateSlouch(degrees: degrees, elapsed: elapsed, at: now)
            }
        }
        lastSample = now
    }

    private func updateSlouch(degrees: Double, elapsed: TimeInterval, at now: Date) {
        let isDown = degrees >= Self.thresholdDegrees
        // A little hysteresis on the label only: sitting up clears it, twitching
        // does not. What earns a nudge is the budget below, not this.
        if isDown {
            isSlouching = true
        } else if degrees < Self.thresholdDegrees - 4 {
            isSlouching = false
        }

        guard let down = budget.record(isDown: isDown, seconds: elapsed, at: now),
              onSlouch?(max(1, Int(down / 60))) == true
        else { return }
        budget.spend(at: now)
    }

    /// How close the current window is to earning a nudge, for the panel.
    var budgetFraction: Double {
        guard isCalibrated else { return 0 }
        return budget.fraction
    }

    private func rolloverIfNeeded(_ now: Date) {
        let today = Calendar.current.startOfDay(for: now)
        guard today != statsDay else { return }
        statsDay = today
        wornSeconds = 0
        slouchedSeconds = 0
        persistTotals(now, force: true)
    }

    // MARK: - Readouts

    var slouchFraction: Double {
        guard wornSeconds > 60 else { return 0 }
        return min(1, slouchedSeconds / wornSeconds)
    }

    var slouchedText: String {
        let minutes = Int(slouchedSeconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    var wornText: String {
        let minutes = Int(wornSeconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// CoreMotion calls these on the queue the updates go to, which is the motion
/// queue rather than the main thread, so each hops over instead of assuming.
extension PostureMonitor: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.availability = .tracking }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self.availability = .unavailable
            self.drop = nil
            self.isSlouching = false
            self.budget.forgetReadings()
            self.lastSample = nil
            self.calibrationSamples = []
        }
    }
}

/// When time spent with the head down has earned a nudge.
///
/// Kept apart from the monitor so the rule can be run against a clock rather
/// than a pair of AirPods: everything it needs is a reading's length, whether
/// it was past the threshold, and when it arrived.
struct SlouchBudget {
    /// How far back the nudge looks.
    ///
    /// Time past the threshold is counted across this window rather than
    /// demanded in one unbroken run. At a desk the angle crosses the line
    /// constantly and rarely stays over it — lifting your head for a moment
    /// used to reset the whole count, which is why the feature tracked
    /// correctly for hours and never once spoke.
    static let windowSeconds: TimeInterval = 180
    /// How much of that window spent down earns a nudge. Long enough that
    /// reading something on the desk is not a slouch, short enough to see it
    /// happen if you deliberately hold your head down.
    static let budgetSeconds: TimeInterval = 90
    /// Quiet period after an alert, so it nags at most a few times an hour.
    static let cooldownSeconds: TimeInterval = 600

    /// One processed reading: how long it covered, and whether it was past the
    /// threshold. Readings are throttled to a couple a second, so a full window
    /// is a few hundred of these.
    private struct Sample {
        let at: Date
        let seconds: TimeInterval
        let isDown: Bool
    }

    private var recent: [Sample] = []
    private var lastNudge: Date?

    /// Seconds spent down within the window.
    var downSeconds: TimeInterval {
        recent.reduce(0) { $0 + ($1.isDown ? $1.seconds : 0) }
    }

    /// How close the window is to earning a nudge.
    var fraction: Double { min(1, downSeconds / Self.budgetSeconds) }

    /// Adds a reading. Returns the time spent down when that has earned a nudge,
    /// and keeps returning it until `spend` says the nudge was actually shown.
    mutating func record(isDown: Bool, seconds: TimeInterval, at now: Date) -> TimeInterval? {
        recent.append(Sample(at: now, seconds: seconds, isDown: isDown))
        let cutoff = now.addingTimeInterval(-Self.windowSeconds)
        recent.removeAll { $0.at < cutoff }

        let down = downSeconds
        guard down >= Self.budgetSeconds else { return nil }
        if let last = lastNudge, now.timeIntervalSince(last) < Self.cooldownSeconds { return nil }
        return down
    }

    /// The nudge reached the screen. Only now does the quiet period start, and
    /// the next one has to be earned from scratch rather than arriving the
    /// moment the quiet period lapses.
    mutating func spend(at now: Date) {
        lastNudge = now
        recent.removeAll()
    }

    /// Drops the readings but not the quiet period: recalibrating or taking
    /// the AirPods out is no reason to nudge again sooner.
    mutating func forgetReadings() {
        recent.removeAll()
    }
}

/// Lets one head-motion sample through every 0.4 seconds of sensor time.
/// Touched only from the monitor's own serial queue, apart from `reset`, which
/// runs while no stream is open.
private final class Thinning: @unchecked Sendable {
    private var last: TimeInterval?

    func admits(at timestamp: TimeInterval) -> Bool {
        if let last, timestamp - last < 0.4, timestamp >= last { return false }
        last = timestamp
        return true
    }

    func reset() { last = nil }
}
