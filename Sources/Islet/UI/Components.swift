import SwiftUI

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

struct Equalizer: View {
    var active: Bool
    var tint: Color = .white
    var height: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0 ..< 4, id: \.self) { index in
                    Capsule()
                        .fill(tint.opacity(active ? 0.9 : 0.35))
                        .frame(width: 2.5, height: height * level(t: t, index: index))
                }
            }
            .frame(height: height)
        }
    }

    private func level(t: Double, index: Int) -> Double {
        guard active else { return 0.22 }
        let speed = [3.1, 4.3, 2.6, 3.7][index]
        let offset = [0.0, 1.2, 2.4, 0.6][index]
        return 0.25 + 0.75 * abs(sin(t * speed + offset))
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

    /// Documentation captures need a stable frame, so ISLET_DEMO pins the text
    /// at the start instead of catching it mid-scroll.
    private static let pinned = ProcessInfo.processInfo.environment["ISLET_DEMO"] != nil

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
                    guard overflow > 6, !Self.pinned else { return }
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
