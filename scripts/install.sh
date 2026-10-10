#!/bin/bash
# Installs AppLock to /Applications and registers it to launch at login.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AppLock"
TARGET="/Applications/$APP_NAME.app"
AGENT_LABEL="com.aryan.applock"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

echo "==> Building app bundle"
"$ROOT/scripts/build-app.sh" release

echo "==> Installing to $TARGET"
pkill -x "$APP_NAME" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
rm -rf "$TARGET"
cp -R "$ROOT/dist/$APP_NAME.app" "$TARGET"

echo "==> Registering login item"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$TARGET/Contents/MacOS/$APP_NAME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"

echo ""
echo "AppLock is installed and running. It will start automatically at login."
echo "Open the manager from the menu bar lock icon."
