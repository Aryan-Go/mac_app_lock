#!/bin/bash
# Removes AppLock: the app bundle, the login item and stored config.
set -euo pipefail

APP_NAME="AppLock"
TARGET="/Applications/$APP_NAME.app"
AGENT_LABEL="com.aryan.applock"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
SUPPORT="$HOME/Library/Application Support/AppLock"

echo "==> Quitting $APP_NAME"
pkill -x "$APP_NAME" 2>/dev/null || true

echo "==> Removing login item"
launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
rm -f "$AGENT_PLIST"

echo "==> Removing app bundle"
rm -rf "$TARGET"

echo "==> Removing config"
rm -rf "$SUPPORT"

echo "AppLock has been removed. Passcode entries stay in your Keychain as 'com.aryan.applock'."
echo "Delete them from Keychain Access if you want a truly clean slate."
