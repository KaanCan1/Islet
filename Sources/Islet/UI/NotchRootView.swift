import SwiftUI

struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var music: MusicManager
    @ObservedObject var pomodoro: PomodoroTimer

    private var spring: Animation { .spring(response: 0.36, dampingFraction: 0.78) }

    var body: some View {
        VStack(spacing: 0) {
            body_
            if state.isExpanded {
                tabBar
                    .padding(.top, Layout.tabBarGap)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
            Spacer(minLength: 0)
        }
        .frame(width: Layout.windowWidth, height: Layout.windowHeight, alignment: .top)
        .animation(spring, value: state.isExpanded)
        .animation(spring, value: state.tab)
        .animation(spring, value: state.showsPeek)
        .animation(spring, value: state.activity)
    }

    private var bottomRadius: CGFloat {
        switch state.presentation {
        case .expanded: return 20
        case .activity: return 14
        case .collapsed: return 9
        }
    }

    private var body_: some View {
        ZStack(alignment: .top) {
            NotchShape(topRadius: Layout.shoulder, bottomRadius: bottomRadius)
                .fill(Color.black)
                .overlay(
                    NotchShape(topRadius: Layout.shoulder, bottomRadius: bottomRadius)
                        .stroke(Color.white.opacity(state.isExpanded ? 0.10 : 0), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(state.isExpanded ? 0.5 : 0), radius: 16, y: 8)

            content
                .padding(.horizontal, Layout.shoulder)
                .padding(.top, state.presentation == .collapsed ? 0 : state.notchSize.height)
        }
        .frame(width: state.frameSize.width, height: state.frameSize.height)
        .opacity(state.chromeOpacity)
    }

    @ViewBuilder
    private var content: some View {
        if let activity = state.activity, !state.isExpanded {
            ActivityView(activity: activity)
                .transition(.opacity)
        } else if state.isExpanded {
            Group {
                switch state.tab {
                case .music: MusicPanel(music: music, state: state, claude: state.claude)
                case .timer: TimerPanel(pomodoro: pomodoro, state: state)
                case .claude: ClaudePanel(claude: state.claude)
                }
            }
            .transition(.opacity)
        } else {
            CollapsedView(state: state, music: music, pomodoro: pomodoro)
                .transition(.opacity)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(state.visibleTabs) { tab in
                Button {
                    state.tab = tab
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(state.tab == tab ? .white : .white.opacity(0.45))
                        .frame(width: 29, height: 19)
                        .background(
                            Capsule().fill(Color.white.opacity(state.tab == tab ? 0.16 : 0))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule().fill(.black.opacity(0.55))
                .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.8))
        )
        .frame(height: Layout.tabBarHeight)
    }
}

/// The small summary either side of the notch: artwork and equalizer while
/// music plays, remaining time while a timer runs.
struct CollapsedView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var music: MusicManager
    @ObservedObject var pomodoro: PomodoroTimer

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: Layout.peek)
            Spacer(minLength: state.notchSize.width)
            trailing
                .frame(width: Layout.peek)
        }
        .opacity(state.showsPeek ? 1 : 0)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var leading: some View {
        HStack {
            Spacer(minLength: 0)
            if music.track.isPlaying {
                ArtworkView(image: music.artwork, size: state.notchSize.height - 10, corner: 5)
            } else if pomodoro.isRunning {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(pomodoro.mode == .focus ? .orange : .cyan)
            }
        }
        .padding(.trailing, 6)
    }

    @ViewBuilder
    private var trailing: some View {
        HStack {
            if pomodoro.isRunning {
                Text(pomodoro.displayTime)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(pomodoro.mode == .focus ? .orange : .cyan)
                    .monospacedDigit()
            } else if music.track.isPlaying {
                Equalizer(active: true, height: 12)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
    }
}
