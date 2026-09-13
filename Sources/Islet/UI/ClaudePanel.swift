import SwiftUI

/// Detail view for Claude Code usage: both rate-limit windows, how much of each
/// is gone, and when they reset.
///
/// The figures come from Claude's own usage endpoint when its token is
/// reachable, and are estimated from transcripts when it is not — the footnote
/// says which, because the two are not equally trustworthy. See ClaudeUsageAPI
/// and ClaudeUsageMonitor.
struct ClaudePanel: View {
    @ObservedObject var claude: ClaudeUsageMonitor

    /// Refreshes itself every minute; the button forces it early.
    private var status: String {
        if claude.isScanning { return claude.snapshot == nil ? "reading transcripts…" : "refreshing…" }
        guard let updated = claude.snapshot?.updatedAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "updated " + formatter.string(from: updated)
    }

    /// Measured in tokens against a learned ceiling: see ClaudeWindow for why.
    private func footnote(for snapshot: ClaudeUsageMonitor.Snapshot) -> String {
        if snapshot.fiveHour.isExact { return "figures from Claude's usage API" }
        if let failure = claude.apiFailure { return "estimated — " + failure.explanation }
        if snapshot.fiveHour.ceilingTokens == nil && snapshot.sevenDay.ceilingTokens == nil {
            return "estimated — no ceiling learned yet"
        }
        return "estimated from when Claude Code last cut you off"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("CLAUDE CODE")
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                Text(status)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
                    .monospacedDigit()
                IconButton(symbol: "arrow.clockwise", size: 9) { claude.refreshNow() }
                    .disabled(claude.isScanning)
                    .rotationEffect(.degrees(claude.isScanning ? 360 : 0))
                    .animation(
                        claude.isScanning
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: claude.isScanning
                    )
            }

            if let snapshot = claude.snapshot {
                WindowRow(title: "This 5-hour block", window: snapshot.fiveHour)
                WindowRow(title: "Last 7 days", window: snapshot.sevenDay)

                Text(footnote(for: snapshot))
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.28))
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
        guard let percent = window.percent else { return Color(red: 0.87, green: 0.64, blue: 0.46) }
        if percent > 0.85 { return Color(red: 1, green: 0.55, blue: 0.4) }
        if percent > 0.6 { return Color(red: 1, green: 0.78, blue: 0.42) }
        return Color(red: 0.87, green: 0.64, blue: 0.46)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(window.percentText ?? window.usageText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    // With no ceiling learned there is no usage percentage, so the
                    // bar falls back to the window's clock — dimmed, so it doesn't
                    // read as the same measurement.
                    Capsule()
                        .fill(accent.opacity(window.percent == nil ? 0.3 : 0.75))
                        .frame(width: max(3, geo.size.width * (window.percent ?? window.elapsedFraction)))
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
        if window.limitReached {
            return "rate limited · resets in " + window.remainingText
        }
        // Tokens are what the percentage is measured against, so they are what
        // belongs beside it; the minutes are here because they read as effort.
        // The learned ceiling itself is not printed — it is a guess with a wide
        // spread, and putting a number on it made it look like a quoted limit.
        // With no percentage the row's own figure is already the duration, so
        // repeating it here would print the same thing twice.
        var text = window.percentText == nil
            ? "\(window.tokensText) tokens"
            : "\(window.tokensText) tokens in \(window.usageText)"
        if window.resetsAt != nil { text += " · resets in " + window.remainingText }
        return text
    }
}
