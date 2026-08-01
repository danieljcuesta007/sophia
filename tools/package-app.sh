#!/bin/sh
# Package sophia-write into a menu-bar .app bundle (LSUIElement) in dist/.
# Lesson from Cadence's 7/31 regression: verify what actually got bundled —
# this script prints the binary's hash and selftest result at the end.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Sophia Write.app"
BIN="$ROOT/platform-macos/.build/release/sophia-write"

"$ROOT/tools/build.sh"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/sophia-write"

# App icon: regenerate only if missing (assets/mkicon.py needs Chrome).
if [ ! -f "$ROOT/assets/Sophia.icns" ]; then
    python3 "$ROOT/assets/mkicon.py"
fi
cp "$ROOT/assets/Sophia.icns" "$APP/Contents/Resources/Sophia.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Sophia Write</string>
    <key>CFBundleDisplayName</key><string>Sophia Write</string>
    <key>CFBundleIdentifier</key><string>com.sophia.write</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleExecutable</key><string>sophia-write</string>
    <key>CFBundleIconFile</key><string>Sophia</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || true

echo ""
echo "==> packaged: $APP"
shasum -a 256 "$APP/Contents/MacOS/sophia-write" | cut -c1-16
"$APP/Contents/MacOS/sophia-write" selftest | tail -1
