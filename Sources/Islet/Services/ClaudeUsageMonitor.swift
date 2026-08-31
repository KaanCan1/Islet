import Foundation

private let fiveHourWindow: TimeInterval = 5 * 3600
private let sevenDayWindow: TimeInterval = 7 * 86400
/// How far back transcripts are scanned. Long enough to catch the rejections the
/// weekly ceiling is derived from.
private let scanHorizon: TimeInterval = 30 * 86400

/// Usage measured over one rate-limit window.
///
/// Measured as time rather than tokens. Nothing on disk says what Claude counts,
/// so it was worked out from the moments this account was actually cut off:
/// across those, the tokens standing in the window varied by a factor of 3.5
/// (1.2M to 4.3M) while the minutes spent varied far less. Checked against a
/// figure read out of Claude Code's own /usage, the time measure predicted 85%
/// where the truth was 77%; the token measure was out by up to 2x.
struct ClaudeWindow: Equatable {
    /// Seconds in which at least one request was made.
    var usageSeconds: Int
    var tokens: Int
    /// Ceiling in seconds, from the moments this account was rate limited.
    /// Nil when no rejection has been recorded, or when the evidence has gone
    /// stale — being over it without being cut off proves it wrong.
    var ceilingSeconds: Int?
    var resetsAt: Date?
    var limitReached: Bool
    var length: TimeInterval = fiveHourWindow

    var percent: Double? {
        guard let ceilingSeconds, ceilingSeconds > 0 else { return nil }
        return min(Double(usageSeconds) / Double(ceilingSeconds), 1)
    }

    var percentText: String? {
        percent.map { "\(Int(($0 * 100).rounded()))%" }
    }

    static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    var usageText: String { Self.duration(usageSeconds) }
    var ceilingText: String? { ceilingSeconds.map { "~" + Self.duration($0) } }

    var tokensText: String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return "\(tokens / 1_000)K" }
        return "\(tokens)"
    }

    var remainingText: String {
        guard let resetsAt else { return "no reset recorded" }
        let total = Int(max(0, resetsAt.timeIntervalSinceNow))
        let days = total / 86400, hours = (total % 86400) / 3600, minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// How far through the window's clock we are — factual, unlike the ceiling.
    var elapsedFraction: Double {
        guard let resetsAt, length > 0 else { return 0 }
        return min(max(1 - resetsAt.timeIntervalSinceNow / length, 0), 1)
    }
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

    /// Rescans now. Called on a timer every minute, and by the refresh button.
    func refresh() {
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
    /// Bumped when the shape changes, which forces a fresh scan.
    var version = 3
    /// One entry per request, in parallel arrays to keep the file small.
    /// Hourly buckets were not enough: the five-hour window opens with the first
    /// request after the previous one expired, and rounding that to the hour put
    /// the reset time up to an hour out.
    var times: [Double] = []
    var tokens: [Int] = []
    var costs: [Double] = []
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
               let decoded = try? JSONDecoder().decode(Cache.self, from: data),
               decoded.version == Cache().version {
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
        let counts = tokenCounts(in: text)
        guard counts.billable > 0 else { return }
        cache.times.append(date.timeIntervalSince1970)
        cache.tokens.append(counts.billable)
        cache.costs.append(cost(of: counts, model: model(in: text)))
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

    struct TokenCounts {
        var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
        /// What is reported as "used": cache reads are excluded because they
        /// dwarf everything else and drown the signal.
        var billable: Int { input + output + cacheWrite }
    }

    /// Only the top level `usage` object is read — the `iterations` array below it
    /// repeats the same keys and would double count.
    private func tokenCounts(in text: String) -> TokenCounts {
        guard let usage = text.range(of: "\"usage\":{") else { return TokenCounts() }
        let tail = text[usage.upperBound...]
        let end = tail.range(of: "\"iterations\"")?.lowerBound ?? tail.endIndex
        let slice = tail[..<end]
        // The leading quote matters: it stops "input_tokens" matching inside
        // "cache_creation_input_tokens".
        return TokenCounts(
            input: number(after: "\"input_tokens\":", in: slice),
            output: number(after: "\"output_tokens\":", in: slice),
            cacheWrite: number(after: "\"cache_creation_input_tokens\":", in: slice),
            cacheRead: number(after: "\"cache_read_input_tokens\":", in: slice)
        )
    }

    private func model(in text: String) -> String {
        guard let range = text.range(of: "\"model\":\"") else { return "" }
        let rest = text[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return "" }
        return String(rest[..<end])
    }

    /// Published per-million rates: input, output, cache write, cache read.
    /// Subscriptions are not billed this way; this only gives the numbers a
    /// familiar magnitude.
    private func cost(of counts: TokenCounts, model: String) -> Double {
        let rates: (Double, Double, Double, Double)
        switch true {
        case model.contains("opus"): rates = (15, 75, 18.75, 1.5)
        case model.contains("sonnet"): rates = (3, 15, 3.75, 0.3)
        case model.contains("haiku"): rates = (0.8, 4, 1, 0.08)
        default: return 0
        }
        return (Double(counts.input) * rates.0
                + Double(counts.output) * rates.1
                + Double(counts.cacheWrite) * rates.2
                + Double(counts.cacheRead) * rates.3) / 1_000_000
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
        let cutoff = Date().addingTimeInterval(-scanHorizon).timeIntervalSince1970
        var times: [Double] = [], tokens: [Int] = [], costs: [Double] = []
        for index in cache.times.indices where cache.times[index] >= cutoff {
            times.append(cache.times[index])
            tokens.append(cache.tokens[index])
            costs.append(index < cache.costs.count ? cache.costs[index] : 0)
        }
        cache.times = times
        cache.tokens = tokens
        cache.costs = costs
        cache.rejections = cache.rejections.filter { $0.at.timeIntervalSince1970 >= cutoff }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: Summary

    private func summarise() -> ClaudeUsageMonitor.Snapshot? {
        guard !cache.times.isEmpty else { return nil }
        let now = Date().timeIntervalSince1970

        // The window opens with the first request after the previous one ran out,
        // so this needs exact timestamps rather than anything rounded.
        let ordered = cache.times.sorted()
        var blockStart = ordered[0]
        for time in ordered where time - blockStart >= fiveHourWindow { blockStart = time }

        let five = window(from: blockStart, to: now, length: fiveHourWindow,
                          resetsAt: Date(timeIntervalSince1970: blockStart + fiveHourWindow),
                          type: "five_hour")
        let seven = window(from: now - sevenDayWindow, to: now, length: sevenDayWindow,
                           resetsAt: projectedWeeklyReset(now: Date()),
                           type: "seven_day")
        return ClaudeUsageMonitor.Snapshot(fiveHour: five, sevenDay: seven, updatedAt: Date())
    }

    private func window(from start: TimeInterval, to end: TimeInterval, length: TimeInterval,
                        resetsAt: Date?, type: String) -> ClaudeWindow {
        let used = usageSeconds(from: start, to: end)
        let rejected = isRejected(type, now: Date())
        var ceiling = estimatedCeiling(for: type, window: length)
        // Running past the ceiling without being cut off proves it too low, so
        // raise it. That is what keeps this honest as limits move: a promo or a
        // plan change works itself in without anyone typing a number.
        if let value = ceiling, used > value, !rejected { ceiling = used }

        return ClaudeWindow(
            usageSeconds: used,
            tokens: tokens(from: start, to: end),
            ceilingSeconds: ceiling,
            resetsAt: resetsAt,
            limitReached: rejected,
            length: length
        )
    }

    /// Seconds in which at least one request was made, counted in 30-second slots.
    /// Finer slots track the rejections about as well and read less like padding.
    private func usageSeconds(from start: TimeInterval, to end: TimeInterval) -> Int {
        var slots = Set<Int>()
        for time in cache.times where time >= start && time <= end {
            slots.insert(Int(time / 30))
        }
        return slots.count * 30
    }

    private func tokens(from start: TimeInterval, to end: TimeInterval) -> Int {
        var total = 0
        for index in cache.times.indices where cache.times[index] >= start && cache.times[index] <= end {
            total += cache.tokens[index]
        }
        return total
    }

    /// The ceiling, in seconds, from the moments this account was rate limited:
    /// the usage standing in the window at each, taking the largest.
    ///
    /// The largest, not the median, because the measure and whatever Claude
    /// actually counts do not line up exactly — the four rejections here landed
    /// at 50, 64, 88 and 89 minutes. Checked against a figure read out of Claude
    /// Code's own /usage, the largest predicted 72% where the truth was 77%; the
    /// median said 85%. It also cannot report over 100% before a cut-off, which
    /// the median could.
    private func estimatedCeiling(for type: String, window: TimeInterval) -> Int? {
        var values: [Int] = []
        var lastBlock: TimeInterval = -1
        for rejection in cache.rejections.filter({ $0.type == type }).sorted(by: { $0.at < $1.at }) {
            let end = rejection.at.timeIntervalSince1970
            let start = type == "five_hour" ? blockStart(containing: end) : end - window
            // Several rejections in one window describe the same moment.
            guard start != lastBlock else { continue }
            lastBlock = start
            let used = usageSeconds(from: start, to: end)
            if used > 0 { values.append(used) }
        }
        // One rejection is an anecdote, not a ceiling. The single seven-day
        // rejection on this machine predates a "+50% weekly limits" promo and
        // would have reported 99% where the truth was 33%; two agreeing
        // observations are the least that can be stood behind.
        return values.count >= 2 ? values.max() : nil
    }

    private func blockStart(containing moment: TimeInterval) -> TimeInterval {
        var start = cache.times.min() ?? moment
        for time in cache.times.sorted() where time <= moment && time - start >= fiveHourWindow {
            start = time
        }
        return start
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
