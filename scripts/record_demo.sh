#!/usr/bin/env bash
# Re-records docs/demo.mp4 and docs/demo.gif.
#
# Takes over the cursor for about twenty seconds and lays a flat backdrop over
# the strip being recorded, so the demo shows the panel rather than the desktop.
# Whatever is playing in Music or Spotify is what appears in the panel.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Islet.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

command -v ffmpeg >/dev/null || { echo "needs ffmpeg (brew install ffmpeg)"; exit 1; }

echo "==> Building the stage"
swiftc -O "$ROOT/scripts/stage_demo.swift" -o "$WORK/stage"

mkdir -p "$WORK/shelf"
pkill -x Islet 2>/dev/null || true
sleep 1.5
open "$APP" --env ISLET_SCREENSHOT_DIR="$WORK/shelf"
sleep 3

# Give the shelf something to hold, so its tab is in the bar for the tour.
for f in music timer claude; do
	cp "$ROOT/docs/$f.png" "$WORK/shelf/shot-$f.png"
	xattr -w com.apple.metadata:kMDItemIsScreenCapture "1" "$WORK/shelf/shot-$f.png"
	sleep 0.5
done
sleep 5   # let the shelf's own four-second reveal lapse

# The region is centred on the screen and 495x215pt, which is 990x430 at 2x.
CENTRE=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' | awk -F', ' '{print int($3/2)}')
RECT="$((CENTRE - 247)),0,495,215"
echo "==> Recording $RECT"
screencapture -v -C -V 20 -R "$RECT" "$WORK/demo.mov" &
REC=$!
sleep 0.8
"$WORK/stage"
wait $REC 2>/dev/null || true

echo "==> Encoding"
ffmpeg -v error -ss 1.2 -to 19.3 -i "$WORK/demo.mov" \
	-c:v libx264 -pix_fmt yuv420p -crf 23 -r 30 -movflags +faststart -an \
	"$ROOT/docs/demo.mp4" -y
ffmpeg -v error -ss 1.2 -to 19.3 -i "$WORK/demo.mov" \
	-vf "fps=15,scale=700:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" \
	"$ROOT/docs/demo.gif" -y

pkill -x Islet 2>/dev/null || true
echo "==> Done: docs/demo.mp4 $(ls -lh "$ROOT/docs/demo.mp4" | awk '{print $5}'), docs/demo.gif $(ls -lh "$ROOT/docs/demo.gif" | awk '{print $5}')"
