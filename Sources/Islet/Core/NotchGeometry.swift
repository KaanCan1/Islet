import AppKit

/// Measurements of the physical notch, or of a virtual one on displays without it.
struct NotchMetrics: Equatable {
    var screenFrame: CGRect
    var notchSize: CGSize
    var isReal: Bool

    /// The notch in global (bottom-left origin) coordinates.
    var notchRect: CGRect {
        CGRect(
            x: screenFrame.midX - notchSize.width / 2,
            y: screenFrame.maxY - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
    }
}

enum NotchGeometry {
    /// Prefers the built-in display that actually has a notch, falls back to main.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        let frame = screen.frame
        var size = CGSize(width: 0, height: 0)
        var real = false

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            if width > 40 {
                size = CGSize(width: width, height: max(left.height, right.height))
                real = true
            }
        }

        if !real {
            // No notch (external monitor, older Mac): use a virtual one as tall as
            // the menu bar so the panel still has something to anchor to.
            let barHeight = max(NSStatusBar.system.thickness, 24)
            size = CGSize(width: 190, height: barHeight)
        }

        return NotchMetrics(screenFrame: frame, notchSize: size, isReal: real)
    }
}
