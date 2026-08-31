import SwiftUI

struct MusicPanel: View {
    @ObservedObject var music: MusicManager
    @ObservedObject var state: NotchState
    @ObservedObject var claude: ClaudeUsageMonitor

    @State private var artworkHovering = false

    private var track: TrackInfo { music.track }
    private var hasTrack: Bool { !track.isEmpty }

    var body: some View {
        HStack(spacing: 12) {
            artwork
            transport
            if state.prefs.showClaudeUsage {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 58)
                ClaudeUsageColumn(snapshot: claude.snapshot) { state.tab = .claude }
                    .frame(width: 92)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// Tapping the artwork brings the playing app to the front.
    private var artwork: some View {
        ArtworkView(image: music.artwork, size: 78, corner: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(artworkHovering && hasTrack ? 0.25 : 0))
            )
            .overlay(
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(artworkHovering && hasTrack ? 0.9 : 0)
            )
            .animation(.easeOut(duration: 0.15), value: artworkHovering)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onHover { artworkHovering = $0 }
            .onTapGesture { music.activateSource() }
            .help(hasTrack ? "Open in \(track.source.displayName)" : "")
    }

    private var transport: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if hasTrack {
                    MarqueeText(text: track.title, size: 13, weight: .semibold)
                } else {
                    Text("Nothing playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(height: 18, alignment: .leading)
                }
                Equalizer(active: track.isPlaying, height: 12)
            }

            Text(hasTrack ? track.artist : subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)

            Spacer(minLength: 0)

            if hasTrack { progress }
            controls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 78)
    }

    private var subtitle: String {
        music.anyPlayerRunning ? "Start playing something" : "Open Spotify or Music"
    }

    private var progress: some View {
        HStack(spacing: 7) {
            Text(music.position.clockString)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .monospacedDigit()

            SeekBar(
                progress: track.duration > 0 ? music.position / track.duration : 0,
                onScrub: { ratio in music.seek(to: ratio * track.duration) },
                onEditingChanged: { state.interactionLocked = $0 }
            )

            Text("-" + max(0, track.duration - music.position).clockString)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .monospacedDigit()
        }
        .frame(height: 14)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "shuffle", size: 11, isOn: track.shuffle) { music.toggleShuffle() }
                .disabled(!hasTrack)
            Spacer(minLength: 0)
            IconButton(symbol: "backward.fill", size: 14) { music.previous() }
            IconButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 18) { music.playPause() }
                .padding(.horizontal, 4)
            IconButton(symbol: "forward.fill", size: 14) { music.next() }
            Spacer(minLength: 0)
            IconButton(symbol: "repeat", size: 11, isOn: track.repeatOn) { music.toggleRepeat() }
                .disabled(!hasTrack)
        }
        .frame(height: 30)
    }
}

/// Compact five-hour usage beside the transport. Leads with what has actually
/// been spent; the bar is the window's clock, not a share of any limit, because
/// no limit is knowable locally. Tapping it opens the full Claude panel.
struct ClaudeUsageColumn: View {
    var snapshot: ClaudeUsageMonitor.Snapshot?
    var onTap: () -> Void

    @State private var hovering = false

    private var window: ClaudeWindow? { snapshot?.fiveHour }

    private var accent: Color {
        guard let window else { return .white.opacity(0.4) }
        return window.limitReached ? .red : Color(red: 0.87, green: 0.64, blue: 0.46)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CLAUDE")
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(hovering ? 0.55 : 0.35))

            if let window {
                Text(window.limitReached ? "limit" : (window.percentText ?? window.tokensText))
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(accent.opacity(0.85))
                            .frame(width: max(3, geo.size.width * (window.percent ?? window.elapsedFraction)))
                    }
                }
                .frame(height: 3)

                Text(window.remainingText + " left")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                Text("no session")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
        .help("Claude Code usage in this five-hour block — click for the week")
    }
}
