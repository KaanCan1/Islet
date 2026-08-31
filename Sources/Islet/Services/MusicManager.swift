import AppKit
import Combine
import SwiftUI

enum PlayerApp: String, Equatable {
    case none, spotify, music

    var bundleID: String? {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        case .none: return nil
        }
    }

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Apple Music"
        case .none: return "—"
        }
    }

    var isRunning: Bool {
        guard let id = bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }
}

struct TrackInfo: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var duration: Double = 0
    var isPlaying = false
    var shuffle = false
    var repeatOn = false
    var artworkKey = ""
    var source: PlayerApp = .none

    var isEmpty: Bool { title.isEmpty && artist.isEmpty }
}

@MainActor
final class MusicManager: ObservableObject {
    @Published private(set) var track = TrackInfo()
    @Published private(set) var position: Double = 0
    @Published private(set) var artwork: NSImage?
    /// Accent colour pulled from the artwork; used by the progress ring.
    @Published private(set) var accent: Color = .white
    @Published private(set) var anyPlayerRunning = false

    /// Poll more often while the panel is open, less often while it is closed.
    var isActive = false

    private var timer: Timer?
    private var tick = 0
    private var polling = false
    private var lastArtworkKey = ""
    private let artworkPath = NSTemporaryDirectory() + "islet-artwork.dat"

    func start() {
        stop()
        Task { await poll() }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func onTick() {
        tick &+= 1
        // Advance the progress bar locally between polls.
        if track.isPlaying, track.duration > 0 {
            position = min(position + 1, track.duration)
        }
        let interval = isActive ? 1 : 3
        if tick % interval == 0 {
            Task { await poll() }
        }
    }

    // MARK: - Polling

    private func poll() async {
        guard !polling else { return }
        polling = true
        defer { polling = false }

        let candidates: [PlayerApp] = [track.source, .spotify, .music]
            .filter { $0 != .none && $0.isRunning }
            .reduce(into: [PlayerApp]()) { acc, app in if !acc.contains(app) { acc.append(app) } }

        anyPlayerRunning = !candidates.isEmpty
        guard !candidates.isEmpty else {
            reset()
            return
        }

        var fallback: (TrackInfo, Double?)?
        for app in candidates {
            guard let raw = await AppleScriptRunner.shared.run(Self.nowPlayingScript(for: app)),
                  raw != "NA",
                  let parsed = parse(raw, source: app) else { continue }
            if parsed.0.isPlaying {
                apply(parsed.0, position: parsed.1)
                return
            }
            if fallback == nil { fallback = parsed }
        }

        if let fallback {
            apply(fallback.0, position: fallback.1)
        } else {
            reset()
        }
    }

    private func apply(_ info: TrackInfo, position newPosition: Double?) {
        let changed = info != track
        if changed { track = info }
        // A nil position means the player wouldn't report one; keep counting
        // locally rather than snapping the bar back to zero.
        if let newPosition, changed || abs(newPosition - position) > 1.5 {
            position = newPosition
        }
        if info.artworkKey != lastArtworkKey || (artwork == nil && !info.isEmpty) {
            lastArtworkKey = info.artworkKey
            Task { await loadArtwork(for: info) }
        }
    }

    private func reset() {
        if !track.isEmpty || artwork != nil {
            track = TrackInfo()
            position = 0
            artwork = nil
            lastArtworkKey = ""
        }
    }

    private func parse(_ raw: String, source: PlayerApp) -> (TrackInfo, Double?)? {
        let f = raw.components(separatedBy: "\t")
        guard f.count >= 9 else { return nil }
        var info = TrackInfo()
        info.title = f[0]
        info.artist = f[1]
        info.album = f[2]
        info.duration = Double(f[3]) ?? 0
        info.isPlaying = f[5].hasPrefix("playing")
        info.artworkKey = f[6].isEmpty ? "\(source.rawValue):\(f[0])|\(f[2])" : f[6]
        info.shuffle = f[7] == "true"
        info.repeatOn = f[8] == "true"
        info.source = source
        return (info, f[4].isEmpty ? nil : Double(f[4]))
    }

    // MARK: - Artwork

    private func loadArtwork(for info: TrackInfo) async {
        var image: NSImage?
        switch info.source {
        case .spotify:
            if let url = URL(string: info.artworkKey), url.scheme?.hasPrefix("http") == true,
               let (data, _) = try? await URLSession.shared.data(from: url) {
                image = NSImage(data: data)
            }
        case .music:
            let path = artworkPath
            let script = """
            set target to POSIX file "\(path)"
            tell application id "com.apple.Music"
            	set coverData to (raw data of artwork 1 of current track)
            end tell
            set fileRef to (open for access target with write permission)
            try
            	set eof fileRef to 0
            	write coverData to fileRef
            	close access fileRef
            on error
            	try
            		close access fileRef
            	end try
            	return "ERR"
            end try
            return "OK"
            """
            if await AppleScriptRunner.shared.run(script) == "OK" {
                image = NSImage(contentsOfFile: path)
            }
        case .none:
            break
        }
        // The track may have changed while the artwork was loading.
        guard info.artworkKey == lastArtworkKey else { return }
        artwork = image
        accent = image.flatMap(Color.dominant(of:)) ?? .white
    }

    // MARK: - Commands

    func playPause() { command("playpause", mediaKey: .playPause) }
    func next() { command("next track", mediaKey: .next) }
    func previous() { command("previous track", mediaKey: .previous) }

    func toggleShuffle() {
        switch track.source {
        case .spotify: tell("set shuffling to not shuffling")
        case .music: tell("set shuffle enabled to not shuffle enabled")
        case .none: break
        }
        optimistic { $0.shuffle.toggle() }
    }

    func toggleRepeat() {
        switch track.source {
        case .spotify:
            tell("set repeating to not repeating")
        case .music:
            tell("if song repeat is off then\n\tset song repeat to all\nelse\n\tset song repeat to off\nend if")
        case .none:
            break
        }
        optimistic { $0.repeatOn.toggle() }
    }

    func seek(to seconds: Double) {
        guard track.source != .none else { return }
        position = max(0, min(seconds, track.duration))
        tell("set player position to \(Int(position))")
    }

    /// Brings the playing app to the front (tapping the panel header).
    func activateSource() {
        guard let id = track.source.bundleID else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            running.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func command(_ appleScript: String, mediaKey: MediaKeys.Key) {
        if track.source == .none {
            // No supported player: fall back to the system media keys.
            if MediaKeys.isTrusted { MediaKeys.send(mediaKey) } else { MediaKeys.requestTrust() }
            return
        }
        tell(appleScript)
        optimistic { if appleScript == "playpause" { $0.isPlaying.toggle() } }
        // Refresh shortly after the command so the UI catches up.
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            await poll()
        }
    }

    private func optimistic(_ mutate: (inout TrackInfo) -> Void) {
        var copy = track
        mutate(&copy)
        track = copy
    }

    private func tell(_ body: String) {
        guard let id = track.source.bundleID else { return }
        AppleScriptRunner.shared.run("tell application id \"\(id)\"\n\t\(body)\nend tell")
    }

    static func nowPlayingScript(for app: PlayerApp) -> String {
        switch app {
        case .spotify:
            return """
            tell application id "com.spotify.client"
            	set playerStatus to (player state as text)
            	if playerStatus is "stopped" then return "NA"
            	set theTrack to current track
            	set coverURL to ""
            	try
            		set coverURL to (artwork url of theTrack)
            	end try
            	set shuffleFlag to "false"
            	set repeatFlag to "false"
            	try
            		set shuffleFlag to (shuffling as text)
            		set repeatFlag to (repeating as text)
            	end try
            	set trackLength to 0
            	set trackSpot to ""
            	try
            		set trackLength to ((duration of theTrack) div 1000)
            	end try
            	try
            		set trackSpot to (((player position) div 1) as text)
            	end try
            	return (name of theTrack) & tab & (artist of theTrack) & tab & (album of theTrack) & tab & (trackLength as text) & tab & trackSpot & tab & playerStatus & tab & coverURL & tab & shuffleFlag & tab & repeatFlag
            end tell
            """
        case .music:
            return """
            tell application id "com.apple.Music"
            	set playerStatus to (player state as text)
            	if playerStatus is "stopped" then return "NA"
            	set theTrack to current track
            	set shuffleFlag to "false"
            	set repeatFlag to "false"
            	try
            		set shuffleFlag to (shuffle enabled as text)
            		if song repeat is off then
            			set repeatFlag to "false"
            		else
            			set repeatFlag to "true"
            		end if
            	end try
            	set trackKey to ""
            	try
            		set trackKey to (persistent ID of theTrack)
            	end try
            	set trackLength to 0
            	set trackSpot to ""
            	try
            		set trackLength to ((duration of theTrack) div 1)
            	end try
            	try
            		set trackSpot to (((player position) div 1) as text)
            	end try
            	return (name of theTrack) & tab & (artist of theTrack) & tab & (album of theTrack) & tab & (trackLength as text) & tab & trackSpot & tab & playerStatus & tab & trackKey & tab & shuffleFlag & tab & repeatFlag
            end tell
            """
        case .none:
            return ""
        }
    }
}

extension AppleScriptRunner {
    func run(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            run(source) { continuation.resume(returning: $0) }
        }
    }
}
