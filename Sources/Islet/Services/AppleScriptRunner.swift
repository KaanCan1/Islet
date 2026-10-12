import Foundation

struct AppleScriptFailure: Error {
    var code: Int
    var message: String

    var isMissingObject: Bool { code == -1728 }      // no "current track": nothing is playing
    var isUnauthorized: Bool { code == -1743 || code == -600 }  // automation denied, or app not running

    var localizedHint: String {
        if isUnauthorized {
            return "Automation permission denied (System Settings > Privacy & Security > Automation)"
        }
        if isMissingObject {
            return "Nothing is playing"
        }
        return message
    }
}

/// Runs NSAppleScript on one serial queue. NSAppleScript is not thread safe, so
/// an instance is only ever touched from that queue.
///
/// Most scripts are compiled for the one call. The now-playing poll is not: it
/// runs every few seconds for as long as Islet does, with the same text each
/// time, so it is compiled once and kept. Only scripts the caller marks as
/// kept are, which bounds the cache to the handful of fixed polls — commands
/// carry values in their text and would otherwise pile up one per seek.
final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    /// `ISLET_DEBUG=1` logs every AppleScript error, including the quiet ones.
    private let debug = ProcessInfo.processInfo.environment["ISLET_DEBUG"] == "1"
    private let queue = DispatchQueue(label: "dev.notchisland.applescript", qos: .userInitiated)
    /// Compiled scripts by source. Read and written only on `queue`.
    private var kept: [String: NSAppleScript] = [:]

    private init() {}

    /// Delivers the result on the main thread; `nil` when the script failed.
    func run(_ source: String, keep: Bool = false, completion: (@Sendable (String?) -> Void)? = nil) {
        runDetailed(source, keep: keep) { result in
            completion?(try? result.get())
        }
    }

    func runDetailed(_ source: String, keep: Bool = false,
                     completion: @escaping @Sendable (Result<String, AppleScriptFailure>) -> Void) {
        queue.async { [self, debug] in
            let result = execute(source, keep: keep)
            if case .failure(let failure) = result, debug || !failure.isMissingObject {
                NSLog("Islet: AppleScript \(failure.code) — \(failure.message)")
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func execute(_ source: String, keep: Bool) -> Result<String, AppleScriptFailure> {
        var error: NSDictionary?
        let script: NSAppleScript
        if keep, let compiled = kept[source] {
            script = compiled
        } else {
            guard let fresh = NSAppleScript(source: source) else {
                return .failure(AppleScriptFailure(code: 0, message: "Script failed to compile"))
            }
            // Compiled up front only when it is being kept: a one-off compiles
            // as part of running, and doing it twice would be the waste this
            // is here to remove.
            if keep {
                guard fresh.compileAndReturnError(&error) else { return .failure(Self.failure(error)) }
                kept[source] = fresh
            }
            script = fresh
        }
        let output = script.executeAndReturnError(&error)
        if let error { return .failure(Self.failure(error)) }
        return .success(output.stringValue ?? "")
    }

    private static func failure(_ error: NSDictionary?) -> AppleScriptFailure {
        AppleScriptFailure(
            code: error?[NSAppleScript.errorNumber] as? Int ?? 0,
            message: error?[NSAppleScript.errorMessage] as? String ?? "unknown error"
        )
    }
}
