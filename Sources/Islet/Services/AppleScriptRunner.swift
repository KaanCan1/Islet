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

/// Runs NSAppleScript on one serial queue. A fresh instance is created for every
/// call: NSAppleScript is not thread safe, so instances are never shared.
final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    /// `ISLET_DEBUG=1` logs every AppleScript error, including the quiet ones.
    private let debug = ProcessInfo.processInfo.environment["ISLET_DEBUG"] == "1"
    private let queue = DispatchQueue(label: "dev.notchisland.applescript", qos: .userInitiated)

    private init() {}

    /// Delivers the result on the main thread; `nil` when the script failed.
    func run(_ source: String, completion: (@Sendable (String?) -> Void)? = nil) {
        runDetailed(source) { result in
            completion?(try? result.get())
        }
    }

    func runDetailed(_ source: String, completion: @escaping @Sendable (Result<String, AppleScriptFailure>) -> Void) {
        queue.async { [debug] in
            let result = Self.execute(source)
            if case .failure(let failure) = result, debug || !failure.isMissingObject {
                NSLog("Islet: AppleScript \(failure.code) — \(failure.message)")
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func execute(_ source: String) -> Result<String, AppleScriptFailure> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(AppleScriptFailure(code: 0, message: "Script failed to compile"))
        }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if let error {
            return .failure(AppleScriptFailure(
                code: error[NSAppleScript.errorNumber] as? Int ?? 0,
                message: error[NSAppleScript.errorMessage] as? String ?? "unknown error"
            ))
        }
        return .success(output.stringValue ?? "")
    }
}
