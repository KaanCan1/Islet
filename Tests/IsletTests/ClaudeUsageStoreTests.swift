import Foundation
import Testing
@testable import Islet

/// Runs the transcript scanner over transcripts written here, in the shape
/// Claude Code writes them, against a clock the test sets.
@Suite struct ClaudeUsageStoreTests {
    private let hour: TimeInterval = 3600

    /// A ten-minute boundary a few days back. Recent enough that the scanner's
    /// 30-day horizon keeps the files, aligned so block starts come out exact.
    /// Fixed once per run, so every fixture agrees on it.
    static let base = Date(timeIntervalSince1970:
        ((Date().timeIntervalSince1970 - 3 * 86400) / 600).rounded(.down) * 600)
    private var base: Date { Self.base }

    // MARK: - Five-hour window

    @Test func countsBillableTokensOnly() throws {
        let transcripts = try Transcripts()
        // Cache reads dwarf everything else and are left out; the iterations
        // array repeats the same keys and must not be counted again.
        try transcripts.append(usage(at: 10, input: 100, output: 50, cacheWrite: 25, cacheRead: 10_000))

        let window = try #require(transcripts.summary(at: base + hour)).fiveHour
        #expect(window.tokens == 175)
    }

    @Test func inputTokensIsNotReadOutOfCacheCreation() throws {
        let transcripts = try Transcripts()
        try transcripts.append(usage(at: 10, input: nil, cacheWrite: 300))

        let window = try #require(transcripts.summary(at: base + hour)).fiveHour
        #expect(window.tokens == 300)
    }

    @Test func aHalfWrittenLineWaitsForTheRest() throws {
        let transcripts = try Transcripts()
        let second = usage(at: 20, input: 7)
        let cut = second.index(second.startIndex, offsetBy: second.count / 2)
        try transcripts.append(usage(at: 10, input: 5))
        try transcripts.appendRaw(String(second[..<cut]))

        #expect(try #require(transcripts.summary(at: base + hour)).fiveHour.tokens == 5)

        try transcripts.appendRaw(String(second[cut...]) + "\n")
        #expect(try #require(transcripts.summary(at: base + hour)).fiveHour.tokens == 12)
    }

    @Test func rescanningCountsNothingTwice() throws {
        let transcripts = try Transcripts()
        try transcripts.append(usage(at: 10, input: 5))

        #expect(try #require(transcripts.summary(at: base + hour)).fiveHour.tokens == 5)
        #expect(try #require(transcripts.summary(at: base + hour)).fiveHour.tokens == 5)
        // A fresh start picks up where the cache file says it stopped.
        #expect(try #require(transcripts.summary(at: base + hour, fresh: true)).fiveHour.tokens == 5)
    }

    @Test func theWindowOpensWithTheFirstRequestAfterTheLastRanOut() throws {
        let transcripts = try Transcripts()
        try transcripts.append(usage(at: 7, input: 1000))
        try transcripts.append(usage(at: 60, input: 1000))
        // Over five hours after the first: a new window, opened by this one.
        try transcripts.append(usage(at: 6 * 60 + 13, input: 30))
        try transcripts.append(usage(at: 6 * 60 + 30, input: 12))

        let window = try #require(transcripts.summary(at: base + 7 * hour)).fiveHour
        #expect(window.tokens == 42)
        // Claude's resets land on ten-minute boundaries, so the start is
        // aligned down to one: 6h13m opens a window that resets at 11h10m.
        #expect(window.resetsAt == base + 11 * hour + 10 * 60)
    }

    // MARK: - Learned ceiling

    @Test func oneCutOffIsNotACeiling() throws {
        let transcripts = try Transcripts()
        try transcripts.block(at: 0, tokens: 1000, cutOff: true)
        try transcripts.append(usage(at: 20 * 60, input: 100))

        let window = try #require(transcripts.summary(at: base + 21 * hour)).fiveHour
        #expect(window.ceilingTokens == nil)
        #expect(window.percent == nil)
    }

    @Test func theCeilingIsTheMedianCutOff() throws {
        let transcripts = try Transcripts()
        try transcripts.block(at: 0, tokens: 1000, cutOff: true)
        try transcripts.block(at: 6, tokens: 3000, cutOff: true)
        try transcripts.block(at: 12, tokens: 2000, cutOff: true)
        try transcripts.append(usage(at: 20 * 60, input: 500))

        let window = try #require(transcripts.summary(at: base + 21 * hour)).fiveHour
        #expect(window.ceilingTokens == 2000)
        #expect(window.percent == 0.25)
        #expect(window.limitReached == false)
    }

    @Test func anEvenNumberOfCutOffsTakesTheMiddlePair() throws {
        let transcripts = try Transcripts()
        try transcripts.block(at: 0, tokens: 1000, cutOff: true)
        try transcripts.block(at: 6, tokens: 3000, cutOff: true)
        try transcripts.append(usage(at: 20 * 60, input: 500))

        let window = try #require(transcripts.summary(at: base + 21 * hour)).fiveHour
        #expect(window.ceilingTokens == 2000)
    }

    @Test func cutOffsInOneWindowCountOnce() throws {
        let transcripts = try Transcripts()
        // Refused at 1000, worked on to 1500 and refused again: one moment, and
        // the first refusal is the one that measured the limit.
        try transcripts.block(at: 0, tokens: 1000, cutOff: true)
        try transcripts.append(usage(at: 90, input: 500))
        try transcripts.append(rejection(at: 91, type: "five_hour", resetsAt: base + 5 * hour))
        try transcripts.block(at: 6, tokens: 3000, cutOff: true)
        try transcripts.append(usage(at: 20 * 60, input: 500))

        let window = try #require(transcripts.summary(at: base + 21 * hour)).fiveHour
        #expect(window.ceilingTokens == 2000)
    }

    @Test func aCeilingRunPastWithoutACutOffIsRaised() throws {
        let transcripts = try Transcripts()
        try transcripts.block(at: 0, tokens: 1000, cutOff: true)
        try transcripts.block(at: 6, tokens: 3000, cutOff: true)
        try transcripts.append(usage(at: 20 * 60, input: 2500))

        let window = try #require(transcripts.summary(at: base + 21 * hour)).fiveHour
        #expect(window.ceilingTokens == 2500)
        #expect(window.percent == 1)
    }

    @Test func aStandingRejectionIsTheLimit() throws {
        let transcripts = try Transcripts()
        try transcripts.block(at: 0, tokens: 1000, cutOff: true)
        try transcripts.block(at: 6, tokens: 3000, cutOff: true)
        try transcripts.append(usage(at: 20 * 60, input: 2500))
        let resets = base + 24 * hour
        try transcripts.append(rejection(at: 20 * 60 + 1, type: "five_hour", resetsAt: resets))

        let window = try #require(transcripts.summary(at: base + 21 * hour)).fiveHour
        #expect(window.limitReached)
        // The server's reset time beats the one inferred from the first request.
        #expect(window.resetsAt == resets)
        // The refusal is itself a measurement: 1000, 2500 and 3000.
        #expect(window.ceilingTokens == 2500)
    }

    @Test func theLimitLiftsWhenTheRejectionResets() throws {
        let transcripts = try Transcripts()
        try transcripts.block(at: 0, tokens: 1000, cutOff: true)

        let window = try #require(transcripts.summary(at: base + 6 * hour)).fiveHour
        #expect(window.limitReached == false)
    }

    // MARK: - Weekly window and the API

    @Test func theWeeklyResetIsProjectedOnInSevenDaySteps() throws {
        let transcripts = try Transcripts()
        try transcripts.append(usage(at: 10, input: 5))
        try transcripts.append(rejection(at: 11, type: "seven_day", resetsAt: base - 3 * 86400))

        let window = try #require(transcripts.summary(at: base + hour)).sevenDay
        #expect(window.resetsAt == base + 4 * 86400)
    }

    @Test func exactFiguresOverrideTheEstimate() throws {
        let transcripts = try Transcripts()
        try transcripts.append(usage(at: 10, input: 5))
        let resets = base + 3 * hour
        let api = ClaudeUsageAPI.Reading(fiveHour: .init(utilization: 0.42, resetsAt: resets), sevenDay: nil)

        let snapshot = try #require(transcripts.summary(at: base + hour, api: api))
        #expect(snapshot.fiveHour.isExact)
        #expect(snapshot.fiveHour.percent == 0.42)
        #expect(snapshot.fiveHour.resetsAt == resets)
        #expect(snapshot.sevenDay.isExact == false)
    }

    @Test func theEndpointReportsWholePercents() throws {
        let window = try #require(endpointWindow(#"{"utilization": 42, "resets_at": "2026-10-12T15:00:00+00:00"}"#))
        #expect(window.utilization == 0.42)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_791_817_200))

        #expect(endpointWindow(#"{"utilization": 41.5}"#)?.utilization == 0.415)
        #expect(endpointWindow(#"{"utilization": 150}"#)?.utilization == 1)
        #expect(endpointWindow(#"{"resets_at": "2026-10-12T15:00:00Z"}"#) == nil)
    }

    @Test(arguments: [
        "2026-10-12T15:00:00Z",
        "2026-10-12T15:00:00+00:00",
        "2026-10-12T15:00:00.123+00:00",
        "2026-10-12T15:00:00.123456+00:00"
    ])
    func everyResetStampTheEndpointMightSendIsRead(_ stamp: String) throws {
        let window = try #require(endpointWindow(#"{"utilization": 10, "resets_at": "\#(stamp)"}"#))
        let resets = try #require(window.resetsAt)
        #expect(abs(resets.timeIntervalSince1970 - 1_791_817_200) < 1)
    }

    /// Through JSONSerialization, as the response is: a number in it is an
    /// NSNumber, which a Swift literal in a dictionary is not.
    private func endpointWindow(_ json: String) -> ClaudeUsageAPI.Window? {
        ClaudeUsageAPI.window(try? JSONSerialization.jsonObject(with: Data(json.utf8)))
    }

    // MARK: - Fixtures

    private func usage(at minutes: Double, input: Int?, output: Int = 0, cacheWrite: Int = 0,
                       cacheRead: Int = 0) -> String {
        Self.usage(at: minutes, input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
    }

    private func rejection(at minutes: Double, type: String, resetsAt: Date) -> String {
        Self.rejection(at: minutes, type: type, resetsAt: resetsAt)
    }

    /// One assistant turn, as a transcript line. `minutes` is from `base`.
    static func usage(at minutes: Double, input: Int?, output: Int = 0, cacheWrite: Int = 0,
                       cacheRead: Int = 0) -> String {
        let inputKey = input.map { "\"input_tokens\":\($0)," } ?? ""
        return """
        {"type":"assistant","timestamp":"\(stamp(base + minutes * 60))","message":{"model":"claude-opus-4-1",\
        "usage":{"cache_creation_input_tokens":\(cacheWrite),\(inputKey)"cache_read_input_tokens":\(cacheRead),\
        "output_tokens":\(output),"iterations":[{"input_tokens":999999,"output_tokens":999999}]}}}
        """
    }

    static func rejection(at minutes: Double, type: String, resetsAt: Date) -> String {
        """
        {"type":"system","timestamp":"\(stamp(base + minutes * 60))",\
        "quotaLimits":{"status":"rejected","rateLimitType":"\(type)","resetsAt":\(Int(resetsAt.timeIntervalSince1970))}}
        """
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// A temporary `~/.claude/projects` with one session file, and a cache file
    /// beside it, removed when the test ends.
    private final class Transcripts {
        let root: URL
        let file: URL
        let cache: URL
        private var store: ClaudeUsageStore
        private var base: Date { ClaudeUsageStoreTests.base }

        init() throws {
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("islet-tests-\(UUID().uuidString)", isDirectory: true)
            root = scratch.appendingPathComponent("projects", isDirectory: true)
            let project = root.appendingPathComponent("-Users-someone-project", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            file = project.appendingPathComponent("session.jsonl")
            FileManager.default.createFile(atPath: file.path, contents: nil)
            cache = scratch.appendingPathComponent("claude-usage.json")
            store = ClaudeUsageStore(root: root, cacheURL: cache)
        }

        deinit {
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }

        func append(_ line: String) throws { try appendRaw(line + "\n") }

        func appendRaw(_ text: String) throws {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        }

        /// A window `hours` from base: requests adding up to `tokens`, and the
        /// cut-off that ended it, resetting five hours after it opened.
        func block(at hours: Double, tokens: Int, cutOff: Bool) throws {
            let start = hours * 60
            try append(usage(at: start + 5, input: tokens / 2))
            try append(usage(at: start + 30, input: tokens - tokens / 2))
            if cutOff {
                try append(rejection(at: start + 31, type: "five_hour",
                                     resetsAt: base + (hours + 5) * 3600))
            }
        }

        func summary(at now: Date, api: ClaudeUsageAPI.Reading? = nil,
                     fresh: Bool = false) -> ClaudeUsageMonitor.Snapshot? {
            if fresh { store = ClaudeUsageStore(root: root, cacheURL: cache) }
            return store.refreshAndSummarise(api: api, now: now)
        }

        private func usage(at minutes: Double, input: Int) -> String {
            ClaudeUsageStoreTests.usage(at: minutes, input: input)
        }

        private func rejection(at minutes: Double, type: String, resetsAt: Date) -> String {
            ClaudeUsageStoreTests.rejection(at: minutes, type: type, resetsAt: resetsAt)
        }
    }
}
