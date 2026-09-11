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
        /// Streaming head angle right now.
        case tracking
    }

    /// How far below upright counts as slouching.
    static let thresholdDegrees: Double = 18
    /// How long it has to stay there before Islet says anything.
    static let holdSeconds: TimeInterval = 150
    /// Quiet period after an alert, so it nags at most a few times an hour.
    static let cooldownSeconds: TimeInterval = 900

    @Published private(set) var availability: Availability = .unavailable
    /// False until a reference angle exists. Nothing is judged before then.
    @Published private(set) var isCalibrated = false
    /// Degrees below the calibrated upright angle; positive means head down.
    @Published private(set) var drop: Double?
    @Published private(set) var isSlouching = false
    @Published private(set) var wornSeconds: TimeInterval = 0
    @Published private(set) var slouchedSeconds: TimeInterval = 0

    /// Fires with the number of minutes the head has been down continuously.
    var onSlouch: ((Int) -> Void)?

    private let manager = CMHeadphoneMotionManager()
    private let prefs = Preferences.shared

    private var slouchingSince: Date?
    private var lastAlert: Date?
    private var lastSample: Date?
    private var statsDay: Date = Calendar.current.startOfDay(for: Date())
    /// AirPods come and go. While the feature is on but nothing is connected,
    /// this keeps looking rather than making you toggle the menu item again.
    private var retry: Timer?
    /// Samples arrive at about 25 Hz; nothing here needs more than a couple a second.
    private var lastProcessed: Date?
    /// First readings after starting, used to settle on an upright angle without
    /// making anyone press a button to get a working feature.
    private var calibrationSamples: [Double] = []
    private static let calibrationCount = 12

    override init() {
        super.init()
        manager.delegate = self
        isCalibrated = prefs.postureCalibrated
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
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.availability != .tracking else { return }
                self.attach()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retry = timer
    }

    func disable() {
        retry?.invalidate()
        retry = nil
        stop()
    }

    private func attach() {
        // Already streaming: say so. Returning without this left the panel
        // believing nothing was connected after AirPods dropped and came back.
        guard !manager.isDeviceMotionActive else {
            availability = .tracking
            return
        }

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

        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if error != nil {
                    self.availability = CMHeadphoneMotionManager.authorizationStatus() == .denied
                        ? .denied : .unavailable
                    return
                }
                guard let motion else { return }
                self.consume(motion)
            }
        }
        availability = .tracking
    }

    private func stop() {
        manager.stopDeviceMotionUpdates()
        availability = .unavailable
        drop = nil
        isSlouching = false
        slouchingSince = nil
        lastSample = nil
        lastProcessed = nil
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
        slouchingSince = nil
    }

    // MARK: - Sampling

    private func consume(_ motion: CMDeviceMotion) {
        let now = Date()
        if let last = lastProcessed, now.timeIntervalSince(last) < 0.4 { return }
        lastProcessed = now

        rolloverIfNeeded(now)

        // No reference angle yet: gather a few seconds and take the middle of
        // them, so the feature works on its own. Whatever you are doing then
        // becomes "upright", which is why the panel keeps offering to redo it.
        guard isCalibrated else {
            calibrationSamples.append(motion.attitude.pitch)
            guard calibrationSamples.count >= Self.calibrationCount else { return }
            setUpright(calibrationSamples.sorted()[calibrationSamples.count / 2])
            return
        }

        // Positive = tipped forward of the calibrated upright angle.
        let degrees = (prefs.uprightPitch - motion.attitude.pitch) * 180 / .pi
        drop = degrees

        // Time only accrues between nearby samples. A gap means the AirPods were
        // out or the Mac was asleep, and that is not time spent sitting badly.
        if let last = lastSample {
            let elapsed = now.timeIntervalSince(last)
            if elapsed <= 2 {
                wornSeconds += elapsed
                if degrees >= Self.thresholdDegrees { slouchedSeconds += elapsed }
            }
        }
        lastSample = now

        updateSlouch(degrees: degrees, now: now)
    }

    private func updateSlouch(degrees: Double, now: Date) {
        guard degrees >= Self.thresholdDegrees else {
            // A little hysteresis: sitting up clears it, twitching does not.
            if degrees < Self.thresholdDegrees - 4 {
                isSlouching = false
                slouchingSince = nil
            }
            return
        }

        isSlouching = true
        guard let since = slouchingSince else {
            slouchingSince = now
            return
        }

        let held = now.timeIntervalSince(since)
        guard held >= Self.holdSeconds else { return }
        if let last = lastAlert, now.timeIntervalSince(last) < Self.cooldownSeconds { return }

        lastAlert = now
        onSlouch?(max(1, Int(held / 60)))
    }

    private func rolloverIfNeeded(_ now: Date) {
        let today = Calendar.current.startOfDay(for: now)
        guard today != statsDay else { return }
        statsDay = today
        wornSeconds = 0
        slouchedSeconds = 0
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

extension PostureMonitor: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        MainActor.assumeIsolated { self.availability = .tracking }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        MainActor.assumeIsolated {
            self.availability = .unavailable
            self.drop = nil
            self.isSlouching = false
            self.slouchingSince = nil
            self.lastSample = nil
            self.calibrationSamples = []
        }
    }
}
