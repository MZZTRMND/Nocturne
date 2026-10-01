#!/bin/bash
# Builds Nocturne.app from the SwiftPM executable.
#
#   make-app.sh          → Nocturne.app       (com.nocturne.synth)
#   make-app.sh --test   → Nocturne-Test.app  (com.nocturne.synth.test, "Nocturne Test")
#
# New features are tried in the test build first; the real app is only rebuilt once
# they're approved.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="Nocturne.app"
BUNDLE_ID="com.nocturne.synth"
NAME="Nocturne"
if [[ "${1:-}" == "--test" ]]; then
    APP="Nocturne-Test.app"
    BUNDLE_ID="com.nocturne.synth.test"
    NAME="Nocturne Test"
fi

echo "==> Building release binary"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/Nocturne" "$APP/Contents/MacOS/Nocturne"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Nocturne</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Signing"
codesign --force --deep -s - "$APP" 2>/dev/null
codesign --verify --strict "$APP"

echo
echo "Built $APP — launch with: open $APP"
