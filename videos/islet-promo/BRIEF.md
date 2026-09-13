---
workflow: product-launch-video
flow: automation
storyboard: yes
message: "The notch becomes exactly the panel you need, then disappears"
destination: github-readme
aspect: 1920x1080
language: en
audience: developers on MacBooks
length: 35s
angle: gesture-and-disappearance
narration: no
---

## Intent

A promo for Islet, a macOS app that turns the MacBook's camera notch into a
panel on hover and hides completely when the cursor leaves. It replaces a plain
18-second screen recording in the project README with something designed.

The chosen telling, picked from five: **the gesture and the disappearance**.
Open on the notch growing into a panel — the app's one idea, and the strongest
footage that exists. Carry the middle on the five panels the app actually has.
Close by moving away and leaving nothing on screen, which is the product's own
positioning and the README's opening line.

Tone: quiet and precise, the way the app is. Not a startup sizzle reel — the
audience is developers who distrust one.

## Assets

- /Users/kaancankurt/dev/macos_extentions/docs/music.png — Music panel, window capture, transparent background, 1040px wide
- /Users/kaancankurt/dev/macos_extentions/docs/shelf.png — Screenshot shelf panel, same treatment
- /Users/kaancankurt/dev/macos_extentions/docs/timer.png — Pomodoro timer panel, same treatment
- /Users/kaancankurt/dev/macos_extentions/docs/posture.png — Posture panel, same treatment
- /Users/kaancankurt/dev/macos_extentions/docs/claude.png — Claude usage panel, same treatment
- /Users/kaancankurt/dev/macos_extentions/docs/collapsed.png — the collapsed peek beside the notch, 678x64
- /Users/kaancankurt/dev/macos_extentions/docs/demo.mp4 — 990x430, 18s real screen recording: cursor enters the notch, the panel opens, four tabs are clicked, the cursor leaves and it collapses. The hook and the close come from here.

## Customizations

- The five panel stills are the real thing, captured window-only with alpha. Use
  them as the assets they are; do not rebuild the panel in HTML.
- The notch is the app's shape. The composition may echo it, but the panel
  itself must always be the captured artwork.

## Notes

- **No voiceover.** This plays in a GitHub README, where it is watched muted and
  often without controls. Everything the video says has to be legible on screen.
- The app is free and MIT-licensed, by one person. No pricing beat, no logos of
  customers, no invented metrics. There are none, and inventing them would be
  the fastest way to lose this audience.
- Feature names, verbatim from the README: Music, Shelf, Timer, Posture, Claude.
- The product's own sentence: "Hover your MacBook's camera notch and it grows
  into a panel. Move away and it disappears completely."
- Claude figures shown in the stills are the author's real usage. Fine to show;
  do not fabricate different numbers.
