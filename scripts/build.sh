#!/usr/bin/env bash
# Builds ShiftZones and creates build/ShiftZones.app
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/ShiftZones.app"
IDENTITY="ShiftZones Local Signing"

swift build -c "$CONFIG" --product ShiftZones
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ShiftZones" "$APP/Contents/MacOS/ShiftZones"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# With a stable certificate macOS recognizes the app across builds and the
# Accessibility permission stays valid. With ad-hoc signing it doesn't.
if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "✓ $APP (signed with \"$IDENTITY\")"
else
  codesign --force --sign - "$APP"
  echo "✓ $APP (ad-hoc signature)"
  echo "  Note: after every build macOS treats ShiftZones as a new app and the Accessibility"
  echo "  permission has to be granted again. To avoid that, run once: scripts/create-signing-cert.sh"
fi
