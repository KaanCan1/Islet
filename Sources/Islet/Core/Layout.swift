import CoreGraphics

/// Every size and spacing constant lives here. To add a new tab you only need to
/// touch this file and the `NotchState.Tab` enum.
enum Layout {
    /// Radius of the concave "shoulders" at the top corners. They are what makes
    /// the panel look welded to the notch instead of floating under it.
    static let shoulder: CGFloat = 11

    /// Width of the summary strip that spills out either side of the notch while
    /// collapsed (shown when music is playing or a timer is running).
    static let peek: CGFloat = 66

    /// Body width when expanded, shoulders excluded.
    static let contentWidth: CGFloat = 440

    /// Note: these heights do NOT include the notch strip. They describe the
    /// content area below the physical notch; the total is worked out in NotchState.
    static let musicHeight: CGFloat = 100
    static let timerHeight: CGFloat = 108

    /// Height of a transient alert (battery) below the notch strip.
    static let activityHeight: CGFloat = 26

    static let tabBarHeight: CGFloat = 24
    static let tabBarGap: CGFloat = 7

    /// The window itself never changes size. Expanding animates the SwiftUI body
    /// inside it instead, which avoids clipping and resize jitter.
    static let windowWidth: CGFloat = 620
    static let windowHeight: CGFloat = 250

    /// How far the cursor may stray before the panel collapses again.
    static let hoverSlack: CGFloat = 12
}
