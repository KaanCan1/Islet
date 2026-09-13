---
format: 1920x1080
duration: 35s
fps: 60
message: "The notch becomes exactly the panel you need, then disappears"
arc: Gesture → Name → Five panels → Disappearance
audience: developers on MacBooks, reading a GitHub README with the sound off
mode: autonomous
music: none
---

## Frame 1 — Hover

- scene: The cursor climbs into the notch and it opens into the empty half of the frame
- duration: 4s
- transition_in: cut
- status: animated
- poster: 2.4s
- src: compositions/frames/01-hover.html
- asset_candidates: assets/demo.mp4
- asset_note: 0.0–4.0 — collapsed peek, cursor climbs at 0.7, panel opens on Music at 1.05

The whole product in one gesture, played straight. The footage runs full-bleed
across the **bottom** of the frame and off its edge, so the notch reads as
sitting on a screen that continues past the crop. At `t=0` that half of the
frame is almost entirely the same cream as the page — a collapsed sliver and a
cursor — and the panel then grows down into the emptiness. The frame opens up
rather than cutting to something.

**Shot sequence**

- `0.00` Ground: cream `#F7F5F2`, edge to edge. Footage in at `x:0 y:400 w:1920 h:680`, `object-fit: cover`, from its first frame. No entrance animation on the video — it is already there when the frame starts, and the recording is itself the move.
- `0.15–0.75` Kicker `✱ MACOS · THE CAMERA NOTCH` — JetBrains Mono 28px, 0.16em, uppercase, ink@55% with a coral ✱ — fades up at `x:120 y:100` with a 16px rise, `power2.out`.
- `0.60–1.35` The cursor climbs in the footage. Nothing else moves; the gesture has the frame to itself.
- `1.35–2.15` On the beat the panel opens, the display line **"Hover the notch."** rises 22px into place at `x:120 y:160`, EB Garamond 400, 96px, ink, sentence case, `-0.018em`. `power3.out`, 0.80s.
- `2.05–2.85` Second line **"It becomes a panel."** at `x:120 y:262`, same lockup and move, entering 0.10s behind the first so the pair reads as one sentence arriving in two parts.
- `2.85–4.00` Nothing moves. The open Music panel carries the last beat alone.

## Frame 2 — Islet

- scene: The name, the sentence it has already earned, and what it costs
- duration: 3.6s
- transition_in: crossfade
- status: animated
- poster: 2.4s
- src: compositions/frames/02-islet.html
- asset_candidates: none — type only

The only frame that is pure type, and it comes second on purpose: the name lands
as a label on something already seen, not as a promise ahead of it.

**Shot sequence**

- `0.00–0.80` Ground cream. The wordmark **Islet** sets at `x:120 y:286`, EB Garamond 400, 200px, ink, `-0.028em`. Fades up with a 26px rise, `power3.out`. No scale, no letter-by-letter.
- `0.45–1.15` A 1px ink@12% rule draws left to right under the name, `x:120 → x:1080` at `y:540`, 0.70s `power2.inOut` on `scaleX` from a left origin.
- `0.85–1.60` Lead **"A panel that lives in your MacBook's camera notch, and nowhere else."** — Inter 400, 42px, ink@76%, at `x:120 y:596`, max-width 1240. Fades up, 14px rise.
- `1.55–2.30` Mono index row at `x:120 y:846`: `MIT` `·` `MACOS 14+` `·` `ONE AUTHOR` — JetBrains Mono 26px, 0.16em, uppercase, ink@50%, coral middots. Stagger 0.10s, opacity only.
- `2.30–3.60` Still.

## Frame 3 — Music

- scene: The Music panel, with what it does under it
- duration: 4s
- transition_in: crossfade
- status: animated
- poster: 2.6s
- src: compositions/frames/03-music.html
- asset_candidates: assets/music.png
- asset_note: 1040x360 — "Feeling Good" / Michael Bublé, transport, Claude column at 23%

First of the five, and the frame that sets the tour's grammar: kicker, one serif
line, the real panel, one Inter line beneath. The four frames after it repeat
that skeleton exactly, so a reader comparing features never has to re-find the
layout.

**Shot sequence**

- `0.00–0.60` Kicker `✱ MUSIC` at `x:120 y:112` fades up, 14px rise, `power2.out`.
- `0.10–0.92` Headline **"Now playing, without a window."** at `x:120 y:168`, EB Garamond 400, 88px, ink. 22px rise, `power3.out`.
- `0.25–1.12` Panel capture `assets/music.png` at `x:360 y:327`, 1200x415, fades up with a 30px rise, `power3.out`, 0.87s — the hero, so it is already arriving while the headline is still landing. No scale and no added chrome: the PNG carries its own shadow and tab bar.
- `1.25–1.95` Sub-line **"Spotify or Apple Music. Click the artwork to jump to the app it is playing in."** — Inter 400, 34px, ink@68%, at `x:360 y:790`, max-width 1200. Opacity + 12px rise.
- `1.95–4.00` Still.

## Frame 4 — Shelf

- scene: The shelf panel; the middle tile lifts, the way the cursor lifts it
- duration: 4.2s
- transition_in: crossfade
- status: animated
- poster: 2.9s
- src: compositions/frames/04-shelf.html
- asset_candidates: assets/shelf.png
- asset_note: 1040x376 — "Screenshots · click to open · drag out", three real thumbnails

The one panel whose point is a verb. A still cannot show a drag, so the frame
performs it: the middle tile lifts and a coral hairline draws around it — the
frame's single coral moment.

**Shot sequence**

- `0.00–0.60` Kicker `✱ SHELF` at `x:120 y:112`.
- `0.10–0.92` Headline **"Every screenshot lands here."** at `x:120 y:168`, EB Garamond 400, 88px, ink.
- `0.25–1.12` Panel capture `assets/shelf.png` at `x:360 y:308`, 1200x434, fade + 30px rise.
- `1.55–2.30` The middle tile's footprint — measured inside the scaled art at `x:851 y:446`, 217x134, 10px radius — takes a 2px coral ring at 0 → 1 opacity while the ring and its tile lift `y:-12px` together, `power2.out`, 0.75s. It stays lifted; nothing returns.
- `1.90–2.60` Sub-line **"Click one to open it. Drag it straight into Finder, a chat, a mail draft."** at `x:360 y:790`, Inter 400, 34px, ink@68%.
- `2.60–4.20` Still.

## Frame 5 — Timer

- scene: The timer panel, and the reason it is in a notch instead of a window
- duration: 3.6s
- transition_in: crossfade
- status: animated
- poster: 2.4s
- src: compositions/frames/05-timer.html
- asset_candidates: assets/timer.png
- asset_note: 1040x377 — Focus / Break, tick ruler, Start Timer, 25:00

**Shot sequence**

- `0.00–0.60` Kicker `✱ TIMER` at `x:120 y:112`.
- `0.10–0.92` Headline **"A pomodoro that never takes a window."** at `x:120 y:168`, EB Garamond 400, 88px, ink.
- `0.25–1.12` Panel capture `assets/timer.png` at `x:360 y:307`, 1200x435, fade + 30px rise.
- `1.25–1.95` Sub-line **"Focus and Break, battery alerts, and it can stay up on the lock screen."** at `x:360 y:790`, Inter 400, 34px, ink@68%.
- `1.95–3.60` Still.

## Frame 6 — Posture

- scene: The posture panel — the least believable feature, so it runs longest
- duration: 4.4s
- transition_in: crossfade
- status: animated
- poster: 3.1s
- src: compositions/frames/06-posture.html
- asset_candidates: assets/posture.png
- asset_note: 1040x368 — live AirPods reading: amber "Head down", 27°, past the threshold tick, "10 min down today of 2h 9m worn"

The only feature a reader will not already believe, so it gets the longest frame
and says the mechanism out loud. The reading in the panel is real, taken while
the capture ran; it is never lifted out as a headline number, because the next
person's number will be different.

**Shot sequence**

- `0.00–0.60` Kicker `✱ POSTURE` at `x:120 y:112`.
- `0.10–0.92` Headline **"Your AirPods know your head is dropping."** at `x:120 y:168`, EB Garamond 400, 88px, ink.
- `0.25–1.12` Panel capture `assets/posture.png` at `x:360 y:317`, 1200x425, fade + 30px rise.
- `1.60–2.35` Sub-line, two lines, **"Measured against the upright you set. If it stays down, the notch says so once — and then leaves you alone."** at `x:360 y:790`, Inter 400, 34px, ink@68%, max-width 1200. Opacity + 12px rise, the second line 0.10s behind the first.
- `2.35–4.40` Still.

## Frame 7 — Claude

- scene: The Claude Code usage panel, real figures, nothing else in the frame
- duration: 4s
- transition_in: crossfade
- status: animated
- poster: 2.7s
- src: compositions/frames/07-claude.html
- asset_candidates: assets/claude.png
- asset_note: 1040x453 — "This 5-hour block 13%", "412K tokens in 23m", "Last 7 days 10h 34m", real usage

The densest of the five captures, so it gets the frame to itself — no sub-line
under it. The figures are the author's own usage and are never edited.

**Shot sequence**

- `0.00–0.60` Kicker `✱ CLAUDE CODE` at `x:120 y:112`. On the same beat, right-aligned to `x:1800` on the same baseline, a mono note `TAB DISAPPEARS IF YOU DON'T USE IT` — JetBrains Mono 24px, 0.14em, ink@42% — fades in 0.15s behind the kicker, opacity only.
- `0.10–0.92` Headline **"How much of the five-hour block is gone."** at `x:120 y:168`, EB Garamond 400, 88px, ink.
- `0.25–1.15` Panel capture `assets/claude.png` at `x:360 y:330`, 1200x523, fade + 30px rise, `power3.out`, 0.90s.
- `1.70–2.40` The `23%` figure's row gets a single coral 1px rule drawn beneath it inside the frame's own layer — `x:360 → x:1560` at `y:884` — 0.70s `power2.inOut` on `scaleX` from the left. The frame's one coral moment, and the only thing under the panel.
- `2.40–4.00` Still.

## Frame 8 — Gone

- scene: The cursor leaves, the panel collapses, and the bottom of the frame is left empty
- duration: 5.6s
- transition_in: crossfade
- status: animated
- poster: 4.8s
- src: compositions/frames/08-gone.html
- asset_candidates: assets/demo.mp4
- asset_note: 17.4–21.5 — Claude panel open, cursor leaves at 18.2, collapsed and the strip empty by 19.2

The close is the positioning line, and the footage proves it instead of
illustrating it. The panel collapses, the clip ends, and what is left is the
same cream the recording was standing on — so nothing replaces it, and nothing
needs to.

**Shot sequence**

- `0.00` Footage in at the identical rect to Frame 1 — `x:0 y:400 w:1920 h:680`, `object-fit: cover` — with `data-media-start="17.4"`, so the frame opens on the Claude panel still open and still live. Coming out of Frame 7's still of the same panel at nearly the same size, the crossfade reads as the image waking up rather than as a cut.
- `0.30–1.00` Kicker `✱ MOVE AWAY` at `x:120 y:100`, fades up 16px, `power2.out`.
- `0.85–1.80` In the footage the cursor leaves and the panel collapses, leaving the strip empty. Playback is stopped inside the take before this happens, on purpose: while something is playing a small summary stays beside the notch, so the panel only truly collapses to nothing when nothing is playing. The frame stays completely still against it.
- `2.20–3.00` Display line **"And it's gone."** rises 22px into place at `x:120 y:160`, EB Garamond 400, 128px, ink, `-0.022em`, `power3.out`. It lands **after** the panel has already gone, so the words confirm the screen instead of narrating it.
- `4.10` The clip ends — 4.1s of media in a 5.6s frame. The video leaves the timeline and the frame's own cream, the identical `#F7F5F2`, is what is under it. There is deliberately no fade: both grounds are the same colour, so the only thing that changes is that the moving image stops.
- `3.60–4.35` The one coral moment: `github.com/KaanCan1/Islet` at `x:120 y:330`, JetBrains Mono 500, 38px, coral, with a 1px coral rule drawing left to right under it from `x:120` to `x:800` over 0.55s, `power2.inOut`.
- `4.35–5.60` Still, on an empty cream frame.

## Video direction

**Ground.** One colour under everything: cream `#F7F5F2`. This is not the
preset's stock cream — it is the exact value the screen recording carries, so
the two footage frames meet the page with no visible rectangle. Ink `#141413`
is the voice. Coral `#CC785C` appears **at most once per frame** and never sets
a headline or a body run.

**The footage rect is load-bearing and identical in Frames 1 and 8:**
`x:0 y:400 w:1920 h:680`, `object-fit: cover`. The assembler hoists an approved
`<video>` to the top of the timeline, so that rectangle is **opaque and paints
over anything the frame draws inside it** — every element in Frames 1 and 8
therefore sits at `y < 400`. The source is 990x390 at 60fps; `cover` scales it
1.939x to 1920x756 and crops 38px from the top and bottom. The top crop takes
part of the black notch bar, which is correct: on a real machine the notch is
flush with the top edge of the screen. The bottom crop stops just short of the
parked cursor, which stays in frame.

**Panel captures are never rebuilt and never distorted.** Each PNG is placed at
1200px wide at its own aspect ratio — 1.15x of a 2x retina capture — centred at
`x:360`. They carry their own alpha, their own shadow and their own floating tab
bar; the frame adds no border, no device mockup, no tilt, and no second shadow.

**Every element in every frame ends above `y:900`.** There are no captions in
this video, but the bottom eighth stays clear so the eight frames share one
bottom edge. The only thing that ever crosses it is the hoisted footage, which
is the frame's ground rather than content sitting on it.

**Type.** EB Garamond 400, sentence case, for every display line — 88px across
the five panel frames, 96px on the hook, 128px on the close, 200px for the
wordmark, tracked `-0.018em` to `-0.028em`. Inter 400 for sub-lines at 34px
ink@68% and the lead at 42px. JetBrains Mono 24–38px, uppercase, 0.16em for
kickers and index rows, each kicker opening with the coral ✱. No sans headline,
no serif label, no uppercase serif anywhere.

**One layout for the tour.** Frames 3 through 7 share a skeleton — kicker at
`120,112`; headline at `120,168`; the capture centred at `x:360`; the sub-line
at `x:360 y:790`. Only the capture's `y` moves, set per frame from its own
height so the gap above the sub-line stays even. The repetition is the point.

**Motion doctrine — the whole video is built not to stutter.**

- Only `opacity` and `transform` are ever animated. Nothing animates `top`,
  `left`, `width`, `height`, `filter`, or a shadow.
- One easing family: `power3.out` for entrances, `power2.out` for chrome,
  `power2.inOut` for rules that draw on. No bounce, no elastic, no spring.
- Entrance distance is 12–30px; entrance duration is 0.60–0.90s. The hero of
  each frame — the capture, or the footage — begins arriving inside the first
  0.25s so it is legible almost immediately. At 60fps that
  is 36–54 rendered frames per move, which is what makes them read as smooth
  rather than snapped.
- Nothing enters in under 0.5s, and nothing scales up from 0.
- Staggers are 0.10s and never more than three elements deep.
- **Every frame is completely still for at least its last 0.8s**, so each
  crossfade starts from a settled image and no cut ever lands mid-move.
- The two footage frames add no motion of their own on top of the video. The
  recording is already a move; animating the plate over it would fight it.

**Transitions.** 0.4s crossfades throughout, except the hard cut into Frame 1 —
the video opens cold.

**Render.** 60fps, high quality, and `--video-frame-format png`, so the
recording's flat cream and hard black come through without JPEG ringing at the
panel edges.
