#!/usr/bin/env bash
# Recaptures the panel screenshots in docs/.
#
# Each shot is a window capture, so nothing behind or beside the panel is ever
# in the image. ISLET_DEMO holds the panel open on one tab; ISLET_SCREENSHOT_DIR
# points the shelf somewhere harmless so the real Desktop is left alone.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Islet.app"
DOCS="$ROOT/docs"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

command -v magick >/dev/null || { echo "needs ImageMagick (brew install imagemagick)"; exit 1; }

echo "==> Building the window-id helper"
swiftc -O "$ROOT/scripts/window_id.swift" -o "$WORK/window_id"

mkdir -p "$WORK/shelf"

launch() {  # launch <tab-or-empty>
	pkill -x Islet 2>/dev/null || true
	sleep 1.5
	if [ -n "${1:-}" ]; then
		open "$APP" --env ISLET_DEMO="$1" --env ISLET_SCREENSHOT_DIR="$WORK/shelf"
	else
		open "$APP" --env ISLET_SCREENSHOT_DIR="$WORK/shelf"
	fi
	sleep 3
}

shoot() {  # shoot <name>
	local id
	# The panel is the window the size of Layout.windowWidth x windowHeight; the
	# status item owns one too, and it is usually listed first.
	id="$("$WORK/window_id" Islet | awk '$2 == 620 && $3 == 250 { print $1; exit }')"
	[ -n "$id" ] || { echo "no Islet panel window found for $1"; exit 1; }
	screencapture -x -l "$id" "$WORK/$1.raw.png"
	# Trims the transparent margin the panel leaves inside its fixed-size window,
	# keeping the shadow, which has alpha of its own.
	magick "$WORK/$1.raw.png" -trim +repage "$DOCS/$1.png"
	echo "    docs/$1.png  $(magick identify -format '%wx%h' "$DOCS/$1.png")"
}

for tab in music timer posture claude; do
	echo "==> $tab"
	launch "$tab"
	shoot "$tab"
done

echo "==> shelf"
launch shelf
# Dropped after the watcher is armed, otherwise they count as files that were
# already there. The project's own screenshots stand in for captures.
for f in music timer claude; do
	cp "$DOCS/$f.png" "$WORK/shelf/shot-$f.png"
	xattr -w com.apple.metadata:kMDItemIsScreenCapture "1" "$WORK/shelf/shot-$f.png"
	sleep 0.6
done
sleep 1.5
shoot "shelf"

echo "==> collapsed"
launch ""
shoot "collapsed"

pkill -x Islet 2>/dev/null || true
echo "==> Done."
