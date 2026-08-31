# Islet

Hover your MacBook's camera notch and it grows into a panel. Move away and it
disappears completely.

![Islet in action](docs/demo.gif)

<img src="docs/music.png" width="470" alt="Music panel">
<img src="docs/timer.png" width="470" alt="Timer panel">
<img src="docs/claude.png" width="470" alt="Claude usage panel">

**Music** — now playing from Spotify or Apple Music: large artwork, a scrubbable
progress bar and transport controls. Click the artwork to jump to the app it's
playing in. **Claude** — how much you have spent in the current Claude Code
five-hour block, next to it; click for the week too. **Timer** — a pomodoro with Focus and Break modes.
Plus battery alerts when the charger goes in or out, and an option to stay on
the lock screen.

While something is playing, a small summary sits beside the notch:

<img src="docs/collapsed.png" width="330" alt="Collapsed, with a track playing">

## Install

Needs macOS 14+ and the Xcode Command Line Tools.

```bash
git clone https://github.com/KaanCan1/Islet.git
cd Islet
make install
```

That's it — the app is built, copied to `/Applications` and launched. It lives in
the menu bar with no Dock icon, and every setting is in that menu. Use `make run`
to try it without installing.

## Permissions

On first launch macOS asks for **Automation** ("Islet wants to control Spotify") —
the music panel needs it. **Accessibility** is only requested if you use the
transport buttons while something other than Spotify or Music is playing. Battery
readings need no permission.

## Notes

- Now playing comes from AppleScript, not private APIs: macOS 15.4 closed
  `MediaRemote` to unentitled apps.
- The Claude figures come from `~/.claude/projects/*.jsonl`, read locally — only
  timestamps, token counts and model names, never message content, and nothing
  leaves the machine. Islet asks before it reads any of it, and the whole thing
  stays hidden if you have never used Claude Code.
- **The percentage needs calibrating once.** Claude Code fetches its limits from
  the API and writes them nowhere, and they move (the account this was built on
  had a "+50% weekly limits" promo running). Guessing the ceiling from past rate
  limits was not good enough — the block totals at the moments this account was
  rate limited ranged from 1.2M to 4.3M tokens. So run `/usage` in Claude Code,
  press the target button in the panel, and type the two percentages it reports;
  Islet back-solves the ceilings from what you have already spent and uses them
  from then on. Until you do, it shows an estimate marked with `~`.
- Token totals exclude cache reads, which otherwise dwarf everything else. The
  five-hour window is timed from the first request after the previous window ran
  out, not rounded to the hour — rounding put the reset time up to an hour out.
- Hourly scanning is incremental: only bytes appended since the last pass are
  read, so just the first scan is slow (about 12 seconds for 380 MB of
  transcripts, on a background thread). It refreshes every minute and the panel
  has a refresh button.
- Displays without a notch get a virtual one at the top centre of the screen.
- In full-screen apps macOS slides the menu bar down the moment the cursor
  touches the top edge. That's the system, not Islet. To stop it: System Settings
  → Control Center → Menu Bar → "Automatically hide and show the menu bar" → Never.
- `./dist/Islet.app/Contents/MacOS/Islet --diagnose` prints every screen, the
  detected notch size, permission state and the raw now-playing payload.

## License

MIT — see [LICENSE](LICENSE).
