import SwiftUI

struct MusicPanel: View {
    @ObservedObject var music: MusicManager
    @ObservedObject var state: NotchState

    @State private var headerHovering = false

    private var track: TrackInfo { music.track }
    private var hasTrack: Bool { !track.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if hasTrack {
                progress
            } else {
                Text(music.anyPlayerRunning
                     ? "Start playing something"
                     : "Open Spotify or Music — or use the media keys")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 16)
            }
            controls
        }
        .padding(.horizontal, 13)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    /// Tapping the header brings the playing app to the front.
    private var header: some View {
        HStack(spacing: 9) {
            ArtworkView(image: music.artwork, size: 46, corner: 9)
            VStack(alignment: .leading, spacing: 1) {
                if hasTrack {
                    MarqueeText(text: track.title, size: 13, weight: .semibold)
                } else {
                    Text("Nothing playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(height: 18, alignment: .leading)
                }
                Text(hasTrack ? track.artist : track.source.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Equalizer(active: track.isPlaying, height: 14)
        }
        .frame(height: 46)
        .opacity(headerHovering && hasTrack ? 0.75 : 1)
        .contentShape(Rectangle())
        .onHover { headerHovering = $0 }
        .onTapGesture { music.activateSource() }
        .help(hasTrack ? "Open in \(track.source.displayName)" : "")
    }

    private var progress: some View {
        HStack(spacing: 7) {
            Text(music.position.clockString)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 32, alignment: .leading)
                .monospacedDigit()

            SeekBar(
                progress: track.duration > 0 ? music.position / track.duration : 0,
                onScrub: { ratio in music.seek(to: ratio * track.duration) },
                onEditingChanged: { state.interactionLocked = $0 }
            )

            Text("-" + max(0, track.duration - music.position).clockString)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 36, alignment: .trailing)
                .monospacedDigit()
        }
        .frame(height: 16)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "shuffle", size: 12, isOn: track.shuffle) { music.toggleShuffle() }
                .disabled(!hasTrack)
            Spacer(minLength: 0)
            IconButton(symbol: "backward.fill", size: 15) { music.previous() }
            IconButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 19) { music.playPause() }
                .padding(.horizontal, 6)
            IconButton(symbol: "forward.fill", size: 15) { music.next() }
            Spacer(minLength: 0)
            IconButton(symbol: "repeat", size: 12, isOn: track.repeatOn) { music.toggleRepeat() }
                .disabled(!hasTrack)
        }
        .frame(height: 32)
    }
}
