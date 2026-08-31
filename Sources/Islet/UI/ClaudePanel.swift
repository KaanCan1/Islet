import SwiftUI

/// Detail view for Claude Code usage: both rate-limit windows, what has been
/// spent in each, and when they reset.
struct ClaudePanel: View {
    @ObservedObject var claude: ClaudeUsageMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("CLAUDE CODE")
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                if claude.isScanning && claude.snapshot == nil {
                    Text("reading transcripts…")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            if let snapshot = claude.snapshot {
                WindowRow(title: "5-hour window", window: snapshot.fiveHour)
                WindowRow(title: "7-day window", window: snapshot.sevenDay)
            } else {
                Text("No Claude Code sessions in the last 30 days.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

private struct WindowRow: View {
    var title: String
    var window: ClaudeWindow

    private var accent: Color {
        if window.limitReached { return .red }
        guard let percent = window.percent else { return .white.opacity(0.5) }
        if percent > 0.85 { return Color(red: 1, green: 0.55, blue: 0.4) }
        if percent > 0.6 { return Color(red: 1, green: 0.78, blue: 0.42) }
        return Color(red: 0.85, green: 0.62, blue: 0.45)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(window.limitReached ? "limit reached" : window.percentText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(accent.opacity(0.9))
                        .frame(width: max(3, geo.size.width * (window.percent ?? 0)))
                }
            }
            .frame(height: 4)

            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
        }
    }

    private var detail: String {
        let used = window.limit == nil
            ? "\(window.tokensText) tokens"
            : "\(window.tokensText) of \(window.limitText) tokens"
        guard window.resetsAt != nil else { return used }
        return used + " · resets in " + window.remainingText
    }
}
