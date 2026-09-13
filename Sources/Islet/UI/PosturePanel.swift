import SwiftUI

/// Head angle from AirPods, and how much of today has been spent looking down.
///
/// The number is degrees below the angle you calibrated as upright — not a
/// posture score. Calibrating is the whole trick: the sensor's zero depends on
/// how the AirPods sit in your ears, so without a reference the reading means
/// nothing.
struct PosturePanel: View {
    @ObservedObject var posture: PostureMonitor

    /// Samples are actually arriving. AirPods report motion only while worn, so
    /// connected is not the same as tracking, and the panel has to say which.
    private var isLive: Bool { posture.availability == .tracking }

    private var tint: Color {
        guard isLive, posture.isCalibrated else { return .white.opacity(0.6) }
        return posture.isSlouching
            ? Color(red: 1.0, green: 0.72, blue: 0.30)
            : Color(red: 0.35, green: 0.85, blue: 0.45)
    }

    private var drop: Double { max(0, posture.drop ?? 0) }

    /// Nothing to fill the track with when no samples are arriving.
    private var trackFraction: Double { isLive ? min(1, drop / 45) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            angleTrack
            footer
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.top, 5)
        .padding(.bottom, 9)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: !isLive ? "airpods"
                              : (!posture.isCalibrated ? "scope"
                                 : (posture.isSlouching ? "figure.seated.side" : "figure.stand")))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))

            Text(!isLive ? "AirPods idle"
                 : (!posture.isCalibrated ? "Finding upright…"
                    : (posture.isSlouching ? "Head down" : "Upright")))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)

            Spacer(minLength: 0)

            Text(isLive && posture.isCalibrated ? "\(Int(drop.rounded()))°" : "—")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(Capture.pinned ? nil : .default, value: Int(drop.rounded()))
        }
        .frame(height: 26)
    }

    /// Current tilt against the threshold, so the line where Islet starts caring
    /// is visible rather than a number you have to remember.
    private var angleTrack: some View {
        GeometryReader { geo in
            let span = 45.0
            let fraction = trackFraction
            let mark = PostureMonitor.thresholdDegrees / span

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, geo.size.width * fraction))
                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 1.5, height: 12)
                    .offset(x: geo.size.width * mark)
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(
                Capture.pinned ? nil : .spring(response: 0.35, dampingFraction: 0.85),
                value: fraction
            )
        }
        .frame(height: 14)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: { posture.calibrate() }) {
                Text("Set upright")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 92, height: 26)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Sit how you want to sit, then press this. Everything is measured from here.")

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(!isLive ? "connected, not being worn"
                     : (posture.isCalibrated ? "\(posture.slouchedText) down today" : "sit how you mean to sit"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Text(!isLive ? "put them in and this starts"
                     : (posture.isCalibrated ? "of \(posture.wornText) worn" : "or press Set upright now"))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .frame(height: 28)
    }
}
