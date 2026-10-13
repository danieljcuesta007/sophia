#!/bin/sh
# Package sophia-write into a menu-bar .app bundle (LSUIElement) and install it
# to ~/Applications. Lesson from Cadence's 7/31 regression: verify what actually
# got bundled — this script checks the icon and binary it shipped, and fails
# loudly rather than quietly shipping stale art.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$ROOT/dist/Sophia Write.app"
INSTALL="$HOME/Applications/Sophia Write.app"
BIN="$ROOT/platform-macos/.build/release/sophia-write"
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

"$ROOT/tools/build.sh"

# App icon: regenerate only if missing (assets/mkicon.py needs Chrome).
[ -f "$ROOT/assets/Sophia.icns" ] || python3 "$ROOT/assets/mkicon.py"

# The icon resource is named by its own content hash. IconServices caches by
# file, so reusing one filename means new art can be served from a stale cache
# entry forever — which is exactly what happened. A new name each time the art
# changes makes a stale hit impossible.
ICON_HASH="$(shasum -a 256 "$ROOT/assets/Sophia.icns" | cut -c1-8)"
ICON_NAME="AppIcon-$ICON_HASH"
# LaunchServices also keys on version, so move it whenever the bundle changes.
BUILD_STAMP="$(date +%Y%m%d%H%M%S)"

rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/sophia-write"
cp "$ROOT/assets/Sophia.icns" "$STAGE/Contents/Resources/$ICON_NAME.icns"

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Sophia Write</string>
    <key>CFBundleDisplayName</key><string>Sophia Write</string>
    <key>CFBundleIdentifier</key><string>com.sophia.write</string>
    <key>CFBundleVersion</key><string>$BUILD_STAMP</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleExecutable</key><string>sophia-write</string>
    <key>CFBundleIconFile</key><string>$ICON_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

echo ""
echo "==> staged: $STAGE"
shasum -a 256 "$STAGE/Contents/MacOS/sophia-write" | cut -c1-16
"$STAGE/Contents/MacOS/sophia-write" selftest | tail -1

# Install to ~/Applications (user-level; no admin needed) so the Dock, Login
# Items, and TCC all point at one stable path across rebuilds. Unregister the
# staging copy FIRST: two bundles sharing com.sophia.write left LaunchServices
# resolving the identifier to the wrong one, which is how the Dock kept serving
# an old icon even after the installed bundle was correct.
[ -x "$LSREG" ] && [ -d "$INSTALL" ] && "$LSREG" -u "$INSTALL" 2>/dev/null || true
rm -rf "$INSTALL"
mkdir -p "$HOME/Applications"
cp -R "$STAGE" "$INSTALL"
[ -x "$LSREG" ] && "$LSREG" -u "$STAGE" 2>/dev/null || true
rm -rf "$ROOT/dist"   # a build artifact, not a second installed copy

# Sign AFTER the bundle is final — signing then editing invalidates the seal.
codesign --force --deep --sign - "$INSTALL" 2>/dev/null || true

echo "==> installed: $INSTALL"

# Verify what actually shipped (never trust that the build did what the source says).
if ! diff -q "$ROOT/assets/Sophia.icns" "$INSTALL/Contents/Resources/$ICON_NAME.icns" >/dev/null; then
    echo "!!  bundled icon differs from assets/Sophia.icns"
    exit 1
fi

# Refresh the icon: register the new bundle, drop the user icon cache, restart
# the Dock. All user-level, no admin.
[ -x "$LSREG" ] && "$LSREG" -f "$INSTALL" 2>/dev/null || true
rm -rf "$HOME/Library/Caches/com.apple.iconservices.store" 2>/dev/null || true
find "$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)" -maxdepth 2 \
    -name "com.apple.iconservices*" -exec rm -rf {} + 2>/dev/null || true
killall Dock 2>/dev/null || true
echo "==> icon $ICON_NAME.icns registered; Dock restarted"
