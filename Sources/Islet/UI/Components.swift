import SwiftUI

// MARK: - Capture mode

/// Documentation captures need a still frame. Anything that animates on its own
/// — a scrolling title, a rolling digit — is smeared by whatever instant the
/// shutter lands on, so ISLET_DEMO holds those at their settled value.
enum Capture {
    static let pinned = ProcessInfo.processInfo.environment["ISLET_DEMO"] != nil
}

// MARK: - Icon button

struct IconButton: View {
    var symbol: String
    var size: CGFloat = 15
    var weight: Font.Weight = .semibold
    var tint: Color = .white
    var isOn: Bool = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(tint.opacity(isOn ? 1 : (hovering ? 0.95 : 0.7)))
                .frame(width: size + 14, height: size + 14)
                .background(
                    Circle()
                        .fill(tint.opacity(isOn ? 0.16 : (hovering ? 0.10 : 0)))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Equalizer

/// Four bars bouncing at their own pace while something plays.
///
/// Drawn with Core Animation rather than a SwiftUI timeline. It sits beside the
/// notch for as long as music plays, and the timeline re-ran SwiftUI layout for
/// the whole panel on every frame: six points of CPU, three quarters of what
/// Islet spent sitting idle beside a playing track. Animations added to a layer
/// run in the render server, so the app does nothing per frame.
struct Equalizer: View {
    var active: Bool
    var tint: Color = .white
    var height: CGFloat = 14

    var body: some View {
        EqualizerBars(active: active, tint: NSColor(tint), height: height)
            .frame(width: EqualizerView.width, height: height)
    }
}

private struct EqualizerBars: NSViewRepresentable {
    var active: Bool
    var tint: NSColor
    var height: CGFloat

    func makeNSView(context: Context) -> EqualizerView { EqualizerView() }

    func updateNSView(_ view: EqualizerView, context: Context) {
        view.configure(active: active, tint: tint, height: height)
    }
}

private final class EqualizerView: NSView {
    static let barWidth: CGFloat = 2.5
    static let spacing: CGFloat = 2.5
    static var width: CGFloat { barWidth * 4 + spacing * 3 }

    /// Each bar follows abs(sin(t * speed + offset)): up over half of pi / speed
    /// seconds and back down over the other half, quickest at the bottom.
    private static let speeds: [Double] = [3.1, 4.3, 2.6, 3.7]
    private static let offsets: [Double] = [0.0, 1.2, 2.4, 0.6]

    private var bars: [CALayer] = []
    private var active = false
    private var tint = NSColor.white
    private var height: CGFloat = 0

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        for _ in 0 ..< 4 {
            let bar = CALayer()
            bar.cornerRadius = Self.barWidth / 2
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Purely decorative: clicks belong to whatever is around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(active: Bool, tint: NSColor, height: CGFloat) {
        // Also redone when the bounce has gone missing while it should be
        // running, so nothing has to know what might have stripped it.
        let lost = active && bars[0].animation(forKey: "bounce") == nil
        guard lost || active != self.active || tint != self.tint || height != self.height else { return }
        self.active = active
        self.tint = tint
        self.height = height
        needsLayout = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.backgroundColor = tint.withAlphaComponent(active ? 0.9 : 0.35).cgColor
            bar.bounds.size = CGSize(width: Self.barWidth, height: height * 0.22)
            bar.removeAnimation(forKey: "bounce")
            guard active else { continue }

            let speed = Self.speeds[index]
            let bounce = CABasicAnimation(keyPath: "bounds.size.height")
            bounce.fromValue = height * 0.25
            bounce.toValue = height
            bounce.duration = .pi / (2 * speed)
            bounce.autoreverses = true
            bounce.repeatCount = .infinity
            bounce.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bounce.timeOffset = Self.offsets[index].truncatingRemainder(dividingBy: .pi) / speed
            // The timeline it replaces drew at 20fps; asking for more would only
            // spend the render server's time on four bars.
            bounce.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 20)
            bounce.isRemovedOnCompletion = false
            bar.add(bounce, forKey: "bounce")
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.position = CGPoint(
                x: CGFloat(index) * (Self.barWidth + Self.spacing) + Self.barWidth / 2,
                y: bounds.midY
            )
        }
        CATransaction.commit()
    }
}

// MARK: - Progress / scrub bar

struct SeekBar: View {
    var progress: Double
    var tint: Color = .white
    var onScrub: (Double) -> Void
    var onEditingChanged: (Bool) -> Void

    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geo in
            let shown = dragValue ?? progress
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(tint.opacity(0.95))
                    .frame(width: max(3, geo.size.width * min(max(shown, 0), 1)))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragValue == nil { onEditingChanged(true) }
                        dragValue = min(max(value.location.x / geo.size.width, 0), 1)
                    }
                    .onEnded { value in
                        let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                        dragValue = nil
                        onScrub(ratio)
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 12)
    }
}

// MARK: - Ruler (minute picker)

struct RulerSlider: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 5 ... 60
    var tint: Color = .orange
    var onEditingChanged: (Bool) -> Void = { _ in }

    private let rulerHeight: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            VStack(spacing: 3) {
                Canvas { context, size in
                    let span = Double(range.upperBound - range.lowerBound)
                    for minute in range {
                        let ratio = Double(minute - range.lowerBound) / span
                        let x = ratio * size.width
                        let isMajor = minute % 5 == 0
                        let isCurrent = minute == value
                        let height: CGFloat = isCurrent ? size.height : (isMajor ? size.height * 0.72 : size.height * 0.42)
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x, y: size.height - height))
                        let color: Color = isCurrent ? .white : tint.opacity(isMajor ? 0.75 : 0.35)
                        context.stroke(path, with: .color(color), lineWidth: isCurrent ? 2 : 1.4)
                    }
                }
                .frame(height: rulerHeight)

                // Pointer for the selected value
                Canvas { context, size in
                    let span = Double(range.upperBound - range.lowerBound)
                    let x = Double(value - range.lowerBound) / span * size.width
                    var path = Path()
                    path.move(to: CGPoint(x: x - 4, y: size.height))
                    path.addLine(to: CGPoint(x: x + 4, y: size.height))
                    path.addLine(to: CGPoint(x: x, y: 0))
                    path.closeSubpath()
                    context.fill(path, with: .color(tint))
                }
                .frame(height: 5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        onEditingChanged(true)
                        update(x: drag.location.x, width: width)
                    }
                    .onEnded { drag in
                        update(x: drag.location.x, width: width)
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: rulerHeight + 8)
    }

    private func update(x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let ratio = min(max(Double(x / width), 0), 1)
        let span = Double(range.upperBound - range.lowerBound)
        let minute = Int((ratio * span).rounded()) + range.lowerBound
        let clamped = min(max(minute, range.lowerBound), range.upperBound)
        if clamped != value { value = clamped }
    }
}

// MARK: - Segmented pill

struct SegmentedPill<T: Hashable>: View {
    var options: [(value: T, title: String)]
    @Binding var selection: T
    var tint: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? Color.black.opacity(0.85) : Color.white.opacity(0.65))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(selected ? tint : Color.white.opacity(0.08))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: selection)
    }
}

// MARK: - Marquee for titles that don't fit

/// Scrolls slowly back and forth when the text overflows its container, and
/// stays put when it fits. Width is measured through AppKit on purpose: doing it
/// with SwiftUI preferences means mutating state during layout, which was more
/// trouble than it was worth here.
struct MarqueeText: View {
    var text: String
    var size: CGFloat
    var weight: Font.Weight = .regular
    var color: Color = .white

    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let overflow = max(0, textWidth - geo.size.width)
            Text(text)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .offset(x: offset)
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
                .task(id: "\(text)|\(Int(geo.size.width))") {
                    offset = 0
                    guard overflow > 6, !Capture.pinned else { return }
                    withAnimation(
                        .linear(duration: Double(overflow) / 22)
                        .delay(1.6)
                        .repeatForever(autoreverses: true)
                    ) {
                        offset = -overflow
                    }
                }
        }
        .frame(height: ceil(size * 1.35))
    }

    private var textWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: nsWeight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private var nsWeight: NSFont.Weight {
        switch weight {
        case .semibold: return .semibold
        case .medium: return .medium
        case .bold: return .bold
        default: return .regular
        }
    }
}

// MARK: - Artwork

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var corner: CGFloat = 9

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Helpers

extension Double {
    var clockString: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
