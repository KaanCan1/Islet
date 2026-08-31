import AppKit

/// Turns the percentages Claude Code shows into the ceilings Islet divides by.
///
/// Claude Code fetches its limits from the API and never writes them to disk, and
/// they move — the account this was built on had a "+50% weekly limits" promo
/// running, which left every ceiling guessed from past rate limits badly stale.
/// Reading the real figure across once, and back-solving from tokens already
/// spent, is the only way to make the percentage mean anything.
@MainActor
enum ClaudeCalibration {
    static func run(snapshot: ClaudeUsageMonitor.Snapshot, then refresh: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Calibrate against Claude Code"
        alert.informativeText = "Run /usage in Claude Code and type the two percentages it reports. "
            + "Islet works the ceilings out from what you have already spent in each window, "
            + "and keeps using them until you calibrate again.\n\n"
            + "Leave a field empty to keep the current value."
        alert.alertStyle = .informational

        let fiveField = NSTextField(frame: NSRect(x: 150, y: 30, width: 70, height: 22))
        let weekField = NSTextField(frame: NSRect(x: 150, y: 0, width: 70, height: 22))
        fiveField.placeholderString = "77"
        weekField.placeholderString = "33"

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        for (offset, title) in [(30, "5-hour window shows"), (0, "Weekly window shows")] {
            let label = NSTextField(labelWithString: title + "  %")
            label.frame = NSRect(x: 0, y: CGFloat(offset) + 2, width: 145, height: 18)
            label.alignment = .right
            accessory.addSubview(label)
        }
        accessory.addSubview(fiveField)
        accessory.addSubview(weekField)
        alert.accessoryView = accessory

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear")

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = fiveField

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            apply(fiveField.stringValue, tokens: snapshot.fiveHour.tokens, key: "claudeBlockBudget")
            apply(weekField.stringValue, tokens: snapshot.sevenDay.tokens, key: "claudeWeekBudget")
        case .alertThirdButtonReturn:
            UserDefaults.standard.removeObject(forKey: "claudeBlockBudget")
            UserDefaults.standard.removeObject(forKey: "claudeWeekBudget")
        default:
            return
        }
        refresh()
    }

    /// ceiling = tokens spent / the fraction Claude Code says that represents.
    private static func apply(_ input: String, tokens: Int, key: String) {
        let cleaned = input.trimmingCharacters(in: CharacterSet(charactersIn: " %"))
        guard !cleaned.isEmpty,
              let percent = Double(cleaned.replacingOccurrences(of: ",", with: ".")),
              percent > 0, percent <= 100, tokens > 0
        else { return }
        UserDefaults.standard.set(Int(Double(tokens) / (percent / 100)), forKey: key)
    }
}
