# Asset inventory

No site was captured — Islet has no website. Every asset below is a real capture
of the running app, taken by `scripts/capture_docs.sh` and `scripts/record_demo.sh`
in this repo on 13 Sep 2026, against the current `main`. Nothing here is a mockup,
and nothing in it was retouched.

All five panel stills are **window captures with an alpha channel**: the panel body
sits at the top, a transparent gap follows, and the floating tab bar hangs below it,
centred. There is no background — they composite onto any ground.

| file | size | what it shows |
| --- | --- | --- |
| `assets/music.png` | 1040x360 | Music panel. Album art, "Feeling Good" / Michael Bublé, 0:38 of −3:19, transport row, and the Claude column at the right reading 23% with 4h 28m left. |
| `assets/shelf.png` | 1040x376 | Screenshot shelf. "Screenshots · click to open · drag out" and three real thumbnails of the app's own panels. |
| `assets/timer.png` | 1040x377 | Pomodoro timer. Focus / Break segmented control, a tick ruler with the drag handle, Start Timer, 25:00. |
| `assets/posture.png` | 1040x368 | Posture panel, live from AirPods. Green "Upright", 6°, the fill against the threshold tick, "9 min down today of 2h 4m worn". |
| `assets/claude.png` | 1040x453 | Claude Code usage. "This 5-hour block 23%", 21m of ~1h 32m, resets in 4h 28m; "Last 7 days 9h 53m". Real usage — do not alter the figures. |
| `assets/collapsed.png` | 678x64 | The collapsed peek beside the notch while something plays: album art at the left, a level meter at the right. |
| `assets/demo.mp4` | 990x390, 60fps, 21.65s | The screen recording. Cursor climbs into the notch (~0.7–1.05s), the panel opens on Music, then Shelf, Timer, Posture, Claude are clicked in turn; playback is stopped, the cursor leaves at 18.25s and the strip is empty from 19.2s. Ground is flat cream `#F7F5F2`, laid down by the recorder. Every frame is a keyframe so the promo renderer can seek it exactly. |

## Timing map for `demo.mp4`

Measured off the encoded file, in seconds:

| moment | at |
| --- | --- |
| collapsed peek, cursor parked below | 0.0 |
| cursor starts climbing | 0.7 |
| panel opens on Music | 1.05 |
| panel fully drawn | 1.5 |
| Shelf | 4.4 |
| Timer | 7.5 |
| Posture | 10.6 |
| Claude | 13.7 |
| playback stopped, so no peek will remain | 17.0 |
| cursor starts leaving | 18.25 |
| collapsed, nothing on the strip | 19.2 |
| end of clip | 21.65 |

## Brand

No logo file, no wordmark, no brand colors — the app ships none. The panel's own
black-on-cream is the only identity there is, and the video's palette comes from
the frame preset rather than from the product.
