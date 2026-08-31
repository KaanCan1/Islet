import SwiftUI

/// Slim presentation of a transient alert (battery) below the notch strip.
struct ActivityView: View {
    var activity: NotchActivity

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(activity.accent)
                .frame(width: 16)
                .contentTransition(.symbolEffect(.replace))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(activity.accent)
                        .frame(width: max(4, geo.size.width * min(max(activity.level, 0), 1)))
                }
                .frame(height: 5)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)

            if let caption = activity.caption {
                Text(caption)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 13)
        .frame(height: Layout.activityHeight)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: activity)
    }
}
