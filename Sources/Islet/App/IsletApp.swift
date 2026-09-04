import AppKit

@main
struct IsletApp {
    @MainActor
    static func main() {
        // Answers "why does it keep asking for my login password?" on its own,
        // and unlike --diagnose it only inspects the keychain item's access
        // list — it never reads the token, so it cannot cause the prompt it is
        // there to explain.
        if CommandLine.arguments.contains("--keychain-trust") {
            print(ClaudeUsageAPI.keychainTrust())
            return
        }

        if CommandLine.arguments.contains("--diagnose") {
            Diagnostics.run()
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
