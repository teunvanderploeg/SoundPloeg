#!/usr/bin/env bash
set -euo pipefail
APP_PATH="${1:?Usage: verify_app_bundle.sh /path/to/SoundPloeg.app}"
PLIST_PATH="$APP_PATH/Contents/Info.plist"
ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST_PATH")"
[[ "$ICON_FILE" == "AppIcon.icns" ]]
[[ -s "$APP_PATH/Contents/Resources/$ICON_FILE" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST_PATH")" == "com.soundploeg.app" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_PATH")" != "" ]]
echo "App bundle metadata and icon verified."
