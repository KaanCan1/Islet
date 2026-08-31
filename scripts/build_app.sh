#!/usr/bin/env bash
# Builds Islet.app into dist/.
set -euo pipefail

APP_NAME="Islet"
CONFIG="${CONFIG:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

echo "==> Packaging: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# A stable signing identity keeps macOS treating each build as the same app, so
# keychain and Automation grants survive a rebuild. Ad-hoc signatures are derived
# from the code hash, so every build looks like a different program and every
# permission is asked again. Falls back to ad-hoc when no identity is set up.
IDENTITY="${ISLET_SIGN_IDENTITY:-Islet Dev}"
# Not -v: a self-signed identity reports as untrusted, but codesign will
# still sign with it, and that is all this needs.
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
	echo "==> Signing as $IDENTITY"
	codesign --force --sign "$IDENTITY" "$APP"
else
	codesign --force --sign - "$APP"
fi

echo "==> Done: $APP"
