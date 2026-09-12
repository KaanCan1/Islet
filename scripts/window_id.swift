import CoreGraphics
import Foundation

/// Prints the on-screen window ids owned by a process, one per line.
///
/// `screencapture -l` needs a window id, and captures that window alone: no
/// desktop, no other windows, and an alpha channel where the panel is not
/// drawn. That is what keeps whatever is on screen out of the documentation.
let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Islet"
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in info {
    guard let owner = window[kCGWindowOwnerName as String] as? String, owner == target,
          let number = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
    // Size included so the caller can tell the panel from the status item, which
    // is a window of its own and often comes first.
    print("\(number) \(Int(bounds["Width"] ?? 0)) \(Int(bounds["Height"] ?? 0))")
}
