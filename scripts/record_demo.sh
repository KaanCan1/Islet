#!/usr/bin/env bash
# Re-records docs/demo.mp4 and docs/demo.gif.
#
# Takes over the cursor for about twenty seconds and lays a flat backdrop over
# the strip being recorded, so the demo shows the panel rather than the desktop.
# Whatever is playing in Music or Spotify is what appears in the panel.
#
# Writes a 60fps master. ISLET_DEMO_OUT names a directory to write into, which
# is how the promo project takes the footage without touching docs/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Islet.app"
OUT="${ISLET_DEMO_OUT:-$ROOT/docs}"
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

# The reveal leaves the shelf tab selected, so without this the take opens on
# Screenshots instead of Music.
echo "==> Selecting the opening tab"
"$WORK/stage" --preselect music
sleep 1.5

# Centred on the notched screen and 495x215pt, which is 990x430 at 2x. The stage
# owns the geometry; asking Finder for the desktop returns the union of every
# display, which centres the strip between two screens when a second is attached.
RECT="$("$WORK/stage" --rect)"
echo "==> Recording $RECT"
screencapture -v -C -V 28 -R "$RECT" "$WORK/demo.mov" &
REC=$!
sleep 0.8
STAGE_PAUSE_MUSIC="${ISLET_DEMO_PAUSE_MUSIC:-1}" "$WORK/stage"
wait $REC 2>/dev/null || true

echo "==> Encoding"
mkdir -p "$OUT"
# A near-lossless 60fps master: this is source footage for the promo, and every
# generation after this one is a re-encode of it. Every frame is a keyframe
# because the promo renderer seeks this clip once per output frame, and a sparse
# GOP lands it on the wrong moment. The crop drops the last 40px, where the top
# edge of whatever window sits under the backdrop can show through.
ffmpeg -v error -ss "${ISLET_DEMO_IN:-1.35}" -to "${ISLET_DEMO_OUT_T:-23.0}" -i "$WORK/demo.mov" \
	-vf "crop=990:390:0:0" \
	-c:v libx264 -pix_fmt yuv420p -crf 16 -preset slow -r 60 \
	-x264-params "keyint=1:min-keyint=1:scenecut=0" -movflags +faststart -an \
	"$OUT/demo.mp4" -y

# Kept when asked for, so the take can be re-trimmed without re-recording.
if [ -n "${ISLET_DEMO_KEEP_RAW:-}" ]; then
	cp "$WORK/demo.mov" "$ISLET_DEMO_KEEP_RAW"
	echo "==> Raw kept at $ISLET_DEMO_KEEP_RAW"
fi

pkill -x Islet 2>/dev/null || true
echo "==> Done: $OUT/demo.mp4 $(ls -lh "$OUT/demo.mp4" | awk '{print $5}')"
