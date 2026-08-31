# Islet

A small macOS app that turns the camera notch into something useful. Move the
cursor to the notch and it grows into a panel; move away and it disappears
completely.

- **Music** — now playing from Spotify or Apple Music, with artwork, a scrubbable
  progress bar, play/pause, skip, shuffle and repeat. Click the artwork or title
  to jump to the app it's playing in.
- **Timer** — a pomodoro with Focus and Break modes. Pick the length on the ruler,
  start it, and the remaining time stays visible beside the notch. When it runs
  out the panel opens by itself.
- **Progress ring** — while collapsed, the current track's progress traces the
  outline of the notch in a colour pulled from the album artwork.
- **Battery alerts** — the notch briefly expands when the charger is connected or
  disconnected, and when the battery drops below 20%.
- **Lock screen** — the panel can stay visible above the lock curtain.
- Works on displays without a notch too (external monitor, older Mac): it falls
  back to a virtual notch at the top centre of the screen.

No private media APIs: now-playing comes from AppleScript, because macOS 15.4
closed `MediaRemote` to unentitled apps.

## Install

Requires macOS 14+ and Xcode or the Command Line Tools.

```bash
make install
```

That builds `dist/Islet.app`, copies it to `/Applications` and launches it. To
build and run in place instead:

```bash
make run
```

Islet lives in the menu bar and has no Dock icon. The menu bar item opens the
tabs, toggles the settings and quits the app.

## Permissions

On first launch macOS may ask for two things:

1. **Automation** — "Islet wants to control Spotify". Needed for the music panel.
   Deny it and the panel still opens, it just won't know what's playing.
   (System Settings → Privacy & Security → Automation)
2. **Accessibility** — only requested when something other than Spotify or Music
   is playing, so the transport buttons can emulate the system media keys.
   Entirely optional.

Battery readings use public IOKit APIs and need no permission.

> The app is ad-hoc signed. Every rebuild changes the signature, so macOS may ask
> for Automation permission again. That's expected.

## Usage

| Gesture | Result |
|---|---|
| Move the cursor to the notch | The panel opens |
| Click the artwork or title | Brings Spotify / Music to the front |
| Click or drag the progress bar | Seeks in the track |
| Drag the ruler | Sets the timer length (5–60 min) |
| The pill under the panel | Switches between Music and Timer |
| Move the cursor away | The panel closes |

While something is playing or a timer is running, a small summary appears either
side of the notch (artwork and equalizer, or the remaining time). It can be turned
off from the menu bar item.

## Known limitations

- **White band at the top in full-screen apps.** macOS hides the menu bar in
  full screen and slides it back down — along with the window's title bar — the
  moment the cursor touches the very top row of pixels. That is macOS's own
  behaviour and the panel can't suppress it. The hover zone reaches 8pt below the
  notch so you can open the panel without going all the way to the edge. To get
  rid of it entirely: System Settings → Control Center → Menu Bar →
  "Automatically hide and show the menu bar" → **Never**.
- Now-playing only covers Spotify and Apple Music. Anything else (a browser, say)
  falls back to system media keys, which needs Accessibility permission.
- The lock screen option raises the window above the shielding window level.
  Whether macOS actually renders it there depends on the version — if you don't
  see it on the lock screen, that's the system refusing, not a bug in the panel.
- Volume and brightness are deliberately not shown: macOS already draws its own
  HUD for both, and a second one is noise rather than information.
- The app is not notarized, so anyone else you hand it to gets a Gatekeeper
  warning.

## Troubleshooting

```bash
./dist/Islet.app/Contents/MacOS/Islet --diagnose
```

Prints every screen, the detected notch size, permission state, battery, and the
raw now-playing payload from any running player. If the panel shows up on the
wrong display, look for the `<- panel goes here` line: Islet prefers the built-in
screen that reports a notch and falls back to the main screen.

Two debug hooks:

```bash
# Log every AppleScript error, including the ones normally kept quiet
ISLET_DEBUG=1 open dist/Islet.app
```

```bash
# Hold the panel open on one tab, for reproducible documentation screenshots
ISLET_DEMO=music ./dist/Islet.app/Contents/MacOS/Islet
```

```bash
ISLET_SCRIPT='tell application id "com.spotify.client" to return name of current track' ./dist/Islet.app/Contents/MacOS/Islet --diagnose
```

> Watch out for short AppleScript variable names. Names like `st`, `t` or `pos`
> collide with terms in the target app's dictionary and fail to compile with a
> `-2741` error, which is why the player scripts use names like `playerStatus`
> and `theTrack`.

## How it works

The panel has three presentations: **collapsed** (invisible, or the small peek
beside the notch), **activity** (a slightly taller notch for battery alerts) and
**expanded** (the full panel). `NotchState.presentation` decides which one is
current, and all the sizes follow from it.

The window itself never changes size. It stays at `Layout.windowWidth ×
windowHeight` pinned over the notch, and opening or closing animates the SwiftUI
body inside it — resizing the window instead would clip the animation. While
collapsed the panel sets `ignoresMouseEvents = true`, so clicks pass straight
through to the menu bar underneath.

Hover is detected in `NotchController.tick()`, which reads `NSEvent.mouseLocation`
30 times a second and compares it against `NotchState.collapsedHitRect` and
`expandedHitRect`. The expanded region is larger than the collapsed one, so the
panel doesn't flicker at the boundary.

The expanded panel deliberately leaves its top strip empty, as tall as the notch:
the physical notch sits there, so anything drawn in that band would be hidden
behind the camera housing.

## Code map

```
Sources/Islet/
  App/
    IsletApp.swift         entry point (including --diagnose)
    AppDelegate.swift      menu bar item and its menu
    NotchController.swift  owns the panel, tracks the cursor, opens and closes
    NotchPanel.swift       transparent NSPanel above the menu bar
    Diagnostics.swift      --diagnose output
  Core/
    Layout.swift           every size constant
    NotchGeometry.swift    screen and notch measurement
    NotchState.swift       presentation state, tabs, hover regions
    NotchActivity.swift    transient alert model
    Preferences.swift      UserDefaults and launch at login
  Services/
    MusicManager.swift     now-playing, transport, artwork accent colour
    PomodoroTimer.swift    timer logic
    BatteryMonitor.swift   IOKit power source notifications
    AppleScriptRunner.swift
    MediaKeys.swift        system media key fallback
  UI/
    NotchRootView.swift    root view, tab bar, collapsed state
    NotchShape.swift       notch body with concave shoulders
    ActivityView.swift     battery alert
    MusicPanel.swift / TimerPanel.swift / Components.swift
```

### Adding a tab

1. Add a case to `NotchState.Tab` with an `icon` and a `height`.
2. Write the panel view under `UI/`.
3. Add it to the `switch` in `NotchRootView.content`.

The tab bar and the hover regions update themselves.

## License

MIT — see [LICENSE](LICENSE).
