import Foundation

private let fiveHourWindow: TimeInterval = 5 * 3600
private let sevenDayWindow: TimeInterval = 7 * 86400
/// How far back transcripts are scanned. Long enough to catch the rejections the
/// weekly ceiling is derived from.
private let scanHorizon: TimeInterval = 30 * 86400

/// Usage of one rate-limit window.
struct ClaudeWindow: Equatable {
    var tokens: Int
    /// Ceiling derived from moments the account was actually rate limited.
    /// Nil when no rejection has ever been recorded for this window.
    var limit: Int?
    var resetsAt: Date?
    var limitReached: Bool

    var percent: Double? {
        guard let limit, limit > 0 else { return nil }
        return min(Double(tokens) / Double(limit), 1)
    }

    var percentText: String {
        guard let percent else { return "—" }
        return "\(Int((percent * 100).rounded()))%"
    }

    var remainingText: String {
        guard let resetsAt else { return "no reset recorded" }
        let total = Int(max(0, resetsAt.timeIntervalSinceNow))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func tokenText(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return "\(value / 1_000)K" }
        return "\(value)"
    }

    var tokensText: String { Self.tokenText(tokens) }
    var limitText: String { limit.map { "~" + Self.tokenText($0) } ?? "?" }
}

/// Reads Claude Code's own session transcripts to report how much of the
/// five-hour and seven-day usage windows is gone.
///
/// Only usage metadata is read — timestamps, token counts, and the `quotaLimits`
/// record written when a limit is hit. Message content is never parsed or stored.
///
/// Nothing on disk states the account's actual limits, so the ceilings are
/// derived from moments the account *was* rate limited: the tokens in that
/// window at the moment of rejection is, within one message, the limit.
///
/// Transcripts run to hundreds of megabytes, so hourly totals and per-file read
/// offsets are cached in Application Support and only new bytes are read after
/// the first scan.
@MainActor
final class ClaudeUsageMonitor: ObservableObject {
    struct Snapshot: Equatable {
        var fiveHour: ClaudeWindow
        var sevenDay: ClaudeWindow
        var updatedAt: Date
    }

    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var isScanning = false

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
        guard !isScanning else { return }
        isScanning = true
        queue.async {
            let result = Store.shared.refreshAndSummarise()
            DispatchQueue.main.async {
                self.snapshot = result
                self.isScanning = false
            }
        }
    }

    /// One-shot read for diagnostics.
    nonisolated static func probe() -> Snapshot? { Store.shared.refreshAndSummarise() }
}

// MARK: - Cache and scanning

private struct Rejection: Codable, Equatable {
    var at: Date
    var type: String        // "five_hour" | "seven_day"
    var resetsAt: Date
}

private struct Cache: Codable {
    /// Hour bucket (seconds since epoch, floored to the hour) -> tokens.
    var buckets: [Int: Int] = [:]
    /// File path -> bytes already consumed.
    var offsets: [String: UInt64] = [:]
    var rejections: [Rejection] = []
}

/// Owns the cache file and the incremental scan. Lives off the main actor.
private final class Store: @unchecked Sendable {
    static let shared = Store()

    private let lock = NSLock()
    private var cache = Cache()
    private var loaded = false

    private lazy var cacheURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Islet", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("claude-usage.json")
    }()

    func refreshAndSummarise() -> ClaudeUsageMonitor.Snapshot? {
        lock.lock()
        defer { lock.unlock() }

        if !loaded {
            loaded = true
            if let data = try? Data(contentsOf: cacheURL),
               let decoded = try? JSONDecoder().decode(Cache.self, from: data) {
                cache = decoded
            }
        }

        scan()
        prune()
        save()
        return summarise()
    }

    // MARK: Scan

    private func scan() {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let horizon = Date().addingTimeInterval(-scanHorizon)
        for project in projects {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                guard let modified = values?.contentModificationDate, modified > horizon else { continue }
                read(file)
            }
        }
    }

    /// Reads only the bytes appended since the last pass, in chunks, keeping the
    /// partial trailing line for next time.
    private func read(_ file: URL) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        let key = file.path
        let size = (try? handle.seekToEnd()) ?? 0
        var offset = cache.offsets[key] ?? 0
        if offset > size { offset = 0 }        // file was rotated or truncated
        guard offset < size else { return }
        try? handle.seek(toOffset: offset)

        var remainder = Data()
        while offset < size {
            guard let chunk = try? handle.read(upToCount: 8 * 1024 * 1024), !chunk.isEmpty else { break }
            var data = remainder
            data.append(chunk)

            var consumed = 0
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                var lineStart = 0
                for index in 0 ..< raw.count where raw[index] == 0x0A {
                    if index > lineStart {
                        let slice = Data(raw[lineStart ..< index])
                        ingest(slice)
                    }
                    lineStart = index + 1
                }
                consumed = lineStart
            }

            remainder = consumed < data.count ? data.subdata(in: consumed ..< data.count) : Data()
            offset += UInt64(chunk.count)
        }

        // Only count fully consumed lines, so a half written line is re-read later.
        cache.offsets[key] = size - UInt64(remainder.count)
    }

    private func ingest(_ line: Data) {
        guard let text = String(data: line, encoding: .utf8) else { return }
        if text.contains("\"quotaLimits\"") { ingestRejection(text) }
        guard text.contains("\"usage\"") else { return }
        guard let date = timestamp(in: text) else { return }
        let tokens = tokenCount(in: text)
        guard tokens > 0 else { return }
        let hour = Int(date.timeIntervalSince1970 / 3600) * 3600
        cache.buckets[hour, default: 0] += tokens
    }

    private func ingestRejection(_ text: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let quota = object["quotaLimits"] as? [String: Any],
              (quota["status"] as? String) == "rejected",
              let type = quota["rateLimitType"] as? String,
              let resets = quota["resetsAt"] as? Double,
              let stamp = object["timestamp"] as? String,
              let at = isoFormatter.date(from: stamp)
        else { return }
        let rejection = Rejection(at: at, type: type, resetsAt: Date(timeIntervalSince1970: resets))
        if !cache.rejections.contains(rejection) { cache.rejections.append(rejection) }
    }

    // MARK: Field extraction
    //
    // Hand parsed rather than run through JSONSerialization: these lines can be
    // kilobytes each and there are hundreds of thousands of them.

    private func timestamp(in text: String) -> Date? {
        guard let range = text.range(of: "\"timestamp\":\"") else { return nil }
        let rest = text[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return isoFormatter.date(from: String(rest[..<end]))
    }

    /// Sums the tokens that count as consumption. Cache reads are excluded: they
    /// dwarf everything else and would drown the signal.
    ///
    /// Only the top level `usage` object is read — the `iterations` array below it
    /// repeats the same keys and would double count.
    private func tokenCount(in text: String) -> Int {
        guard let usage = text.range(of: "\"usage\":{") else { return 0 }
        let tail = text[usage.upperBound...]
        let end = tail.range(of: "\"iterations\"")?.lowerBound ?? tail.endIndex
        let slice = tail[..<end]
        // The leading quote matters: it stops "input_tokens" matching inside
        // "cache_creation_input_tokens".
        return number(after: "\"input_tokens\":", in: slice)
            + number(after: "\"output_tokens\":", in: slice)
            + number(after: "\"cache_creation_input_tokens\":", in: slice)
    }

    private func number(after key: String, in slice: Substring) -> Int {
        guard let range = slice.range(of: key) else { return 0 }
        var value = 0
        for character in slice[range.upperBound...] {
            guard let digit = character.wholeNumberValue, character.isNumber else { break }
            value = value * 10 + digit
        }
        return value
    }

    // MARK: Housekeeping

    private func prune() {
        let cutoff = Int(Date().addingTimeInterval(-scanHorizon).timeIntervalSince1970)
        cache.buckets = cache.buckets.filter { $0.key >= cutoff }
        let rejectionCutoff = Date().addingTimeInterval(-scanHorizon)
        cache.rejections = cache.rejections.filter { $0.at >= rejectionCutoff }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: Summary

    private func summarise() -> ClaudeUsageMonitor.Snapshot? {
        guard !cache.buckets.isEmpty else { return nil }
        let now = Date()

        // Five hour block: restart whenever an hour lands five hours past the
        // start of the current block.
        let hours = cache.buckets.keys.sorted()
        var blockStart = hours[0]
        for hour in hours where Double(hour - blockStart) >= fiveHourWindow {
            blockStart = hour
        }
        let fiveTokens = tokens(from: Double(blockStart), to: now.timeIntervalSince1970)
        let fiveReset = Date(timeIntervalSince1970: Double(blockStart) + fiveHourWindow)

        let weekStart = now.timeIntervalSince1970 - sevenDayWindow
        let weekTokens = tokens(from: weekStart, to: now.timeIntervalSince1970)

        let five = ClaudeWindow(
            tokens: fiveTokens,
            limit: derivedLimit(for: "five_hour", window: fiveHourWindow),
            resetsAt: fiveReset,
            limitReached: isRejected("five_hour", now: now)
        )
        let seven = ClaudeWindow(
            tokens: weekTokens,
            limit: derivedLimit(for: "seven_day", window: sevenDayWindow),
            resetsAt: projectedWeeklyReset(now: now),
            limitReached: isRejected("seven_day", now: now)
        )
        return ClaudeUsageMonitor.Snapshot(fiveHour: five, sevenDay: seven, updatedAt: now)
    }

    private func tokens(from start: TimeInterval, to end: TimeInterval) -> Int {
        cache.buckets.reduce(0) { total, entry in
            let hour = Double(entry.key)
            return hour >= start - 3600 && hour <= end ? total + entry.value : total
        }
    }

    /// The tokens standing in the window at the moment of a rejection is the
    /// ceiling. Takes the largest such reading, so a rejection recorded midway
    /// through a partially scanned window can't understate it.
    private func derivedLimit(for type: String, window: TimeInterval) -> Int? {
        let candidates = cache.rejections.filter { $0.type == type }.map { rejection -> Int in
            let end = rejection.at.timeIntervalSince1970
            return tokens(from: end - window, to: end)
        }
        let best = candidates.max() ?? 0
        return best > 0 ? best : nil
    }

    private func isRejected(_ type: String, now: Date) -> Bool {
        cache.rejections.contains { $0.type == type && $0.resetsAt > now }
    }

    /// Weekly limits reset on a fixed weekday. Project the recorded reset forward
    /// in seven day steps until it lands in the future.
    private func projectedWeeklyReset(now: Date) -> Date? {
        guard let latest = cache.rejections.filter({ $0.type == "seven_day" }).map(\.resetsAt).max()
        else { return nil }
        var reset = latest
        while reset < now { reset.addTimeInterval(sevenDayWindow) }
        return reset
    }
}

nonisolated(unsafe) private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()
