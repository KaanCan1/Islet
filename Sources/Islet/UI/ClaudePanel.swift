import SwiftUI

/// Detail view for Claude Code usage.
///
/// It reports what has been spent, not how close you are to the limit: the
/// account's ceiling is not recorded anywhere locally, and the recorded rate
/// limits do not agree on one — see ClaudeUsageMonitor. A percentage appears
/// only when a budget has been set by hand.
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

    /// Measured as time spent, not tokens: see ClaudeWindow for why.
    private func footnote(for snapshot: ClaudeUsageMonitor.Snapshot) -> String {
        snapshot.fiveHour.ceilingSeconds == nil && snapshot.sevenDay.ceilingSeconds == nil
            ? "no ceiling learned yet — it appears once a limit is hit"
            : "~ ceiling learned from when Claude Code cut you off"
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
                IconButton(symbol: "arrow.clockwise", size: 9) { claude.refresh() }
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
                WindowRow(title: "This 5-hour block", window: snapshot.fiveHour, showsClock: true)
                WindowRow(title: "Last 7 days", window: snapshot.sevenDay, showsClock: false)

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
    /// Only the five-hour row prints its reset time; the week's is further off.
    var showsClock: Bool

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
        var text = window.usageText
        if let ceiling = window.ceilingText { text += " of \(ceiling)" }
        text += " of use"
        if showsClock { text += " · resets in " + window.remainingText }
        return text
    }
}
