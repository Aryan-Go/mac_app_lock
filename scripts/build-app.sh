#!/bin/bash
# Builds AppLock.app into ./dist. No Xcode project required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP_NAME="AppLock"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "==> Done: $APP"
echo "    Run it with: open \"$APP\""
