import Foundation

/// Length of Claude Code's usage window.
private let usageWindow: TimeInterval = 5 * 3600

nonisolated(unsafe) private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

/// Works out how much of Claude Code's current five-hour usage window is gone by
/// reading its own session transcripts under `~/.claude/projects`.
///
/// Only usage metadata is read — timestamps, token counts, and the `quotaLimits`
/// record Claude Code writes when a limit is actually hit. Message content is
/// never parsed or kept.
///
/// There is no live percentage anywhere on disk: `quotaLimits` only appears once
/// a limit has already been reached. So the window is reconstructed the way the
/// community tooling does it — group entries into five-hour blocks starting at
/// the top of the hour of the first message in each block.
@MainActor
final class ClaudeUsageMonitor: ObservableObject {
    struct Snapshot: Equatable {
        var tokens: Int
        var resetsAt: Date
        var limitReached: Bool

        var remaining: TimeInterval { max(0, resetsAt.timeIntervalSinceNow) }

        /// "2h 14m" / "48m"
        var remainingText: String {
            let total = Int(remaining)
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        }

        /// "1.2M" / "340K"
        var tokenText: String {
            if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
            if tokens >= 1_000 { return "\(tokens / 1_000)K" }
            return "\(tokens)"
        }

        /// How far through the five-hour window we are, 0...1.
        var windowProgress: Double {
            1 - min(max(remaining / usageWindow, 0), 1)
        }
    }

    @Published private(set) var snapshot: Snapshot?

    private var timer: Timer?
    private let queue = DispatchQueue(label: "dev.islet.claude-usage", qos: .utility)

    func start() {
        refresh()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        queue.async {
            let result = Self.scan()
            DispatchQueue.main.async { self.snapshot = result }
        }
    }

    /// One-shot read for diagnostics.
    nonisolated static func probe() -> Snapshot? { scan() }

    // MARK: - Transcript scan

    private nonisolated static func scan() -> Snapshot? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        // A block can only have started within the last five hours, so anything
        // older than that plus a margin cannot contribute.
        let cutoff = Date().addingTimeInterval(-usageWindow - 1800)
        var entries: [(date: Date, tokens: Int)] = []
        var quotaReset: Date?

        for project in projects {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                guard let modified, modified > cutoff else { continue }
                parse(tailOf: file, after: cutoff, into: &entries, quotaReset: &quotaReset)
            }
        }

        guard !entries.isEmpty else { return nil }
        entries.sort { $0.date < $1.date }

        // Walk the entries, restarting the block whenever one lands more than five
        // hours after the block began.
        var blockStart = floorToHour(entries[0].date)
        var tokens = 0
        for entry in entries {
            if entry.date.timeIntervalSince(blockStart) >= usageWindow {
                blockStart = floorToHour(entry.date)
                tokens = 0
            }
            tokens += entry.tokens
        }

        var resetsAt = blockStart.addingTimeInterval(usageWindow)
        var limitReached = false
        // A recorded rejection is authoritative: it carries the server's own reset time.
        if let quotaReset, quotaReset > Date() {
            resetsAt = quotaReset
            limitReached = true
        }
        return Snapshot(tokens: tokens, resetsAt: resetsAt, limitReached: limitReached)
    }

    /// Transcripts grow to tens of megabytes; only the tail can hold recent entries.
    private nonisolated static func parse(
        tailOf file: URL,
        after cutoff: Date,
        into entries: inout [(date: Date, tokens: Int)],
        quotaReset: inout Date?
    ) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        let limit: UInt64 = 4_000_000
        let size = (try? handle.seekToEnd()) ?? 0
        let seeked = size > limit
        try? handle.seek(toOffset: seeked ? size - limit : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        // The first line is probably cut in half by the seek.
        if seeked, !lines.isEmpty { lines.removeFirst() }

        for line in lines {
            let hasUsage = line.contains("\"usage\"")
            let hasQuota = line.contains("\"quotaLimits\"")
            guard hasUsage || hasQuota else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }

            if hasQuota,
               let quota = object["quotaLimits"] as? [String: Any],
               let resets = quota["resetsAt"] as? Double {
                let date = Date(timeIntervalSince1970: resets)
                if quotaReset == nil || date > quotaReset! { quotaReset = date }
            }

            guard let stamp = object["timestamp"] as? String,
                  let date = isoFormatter.date(from: stamp), date > cutoff,
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            // Cache reads are excluded: they dwarf everything else and would make
            // the number meaningless as a sense of "how much have I used".
            let tokens = (usage["input_tokens"] as? Int ?? 0)
                + (usage["output_tokens"] as? Int ?? 0)
                + (usage["cache_creation_input_tokens"] as? Int ?? 0)
            if tokens > 0 { entries.append((date, tokens)) }
        }
    }

    private nonisolated static func floorToHour(_ date: Date) -> Date {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
        return Calendar.current.date(from: parts) ?? date
    }
}
