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

# Install to ~/Applications (user-level; no admin needed) so the Dock, Login
# Items, and TCC all point at one stable path across rebuilds.
INSTALL="$HOME/Applications/Sophia Write.app"
mkdir -p "$HOME/Applications"
rm -rf "$INSTALL"
cp -R "$APP" "$INSTALL"
echo "==> installed: $INSTALL"

# Verify what actually got bundled (the Cadence 7/31 lesson: never trust that
# the build shipped what the source says).
if ! diff -q "$ROOT/assets/Sophia.icns" "$INSTALL/Contents/Resources/Sophia.icns" >/dev/null; then
    echo "!!  bundled icon differs from assets/Sophia.icns"
    exit 1
fi

# macOS caches app icons hard: without this the Dock keeps showing the old
# art indefinitely. Re-register with LaunchServices (the Dock's source of
# truth), drop the icon caches, restart the Dock. All user-level, no admin.
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
touch "$INSTALL" "$INSTALL/Contents/Info.plist" "$INSTALL/Contents/Resources/Sophia.icns"
[ -x "$LSREG" ] && "$LSREG" -f "$INSTALL" 2>/dev/null
rm -rf "$HOME/Library/Caches/com.apple.iconservices.store" 2>/dev/null || true
killall Dock 2>/dev/null || true
echo "==> icon refreshed (LaunchServices re-registered, Dock restarted)"
