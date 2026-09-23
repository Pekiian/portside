#!/usr/bin/env bash
set -euo pipefail

# Portside build: test -> release binary -> Portside.app bundle in ./dist
# Usage: ./build.sh [--install]

APP_NAME="Portside"
BUNDLE_ID="com.portside.app"

# Version from git, so every build is identifiable. A tagged commit gives
# "1.2.0", a commit after one "1.2.0-4-gabc1234", a dirty tree a "-dirty"
# suffix, and an untagged or shallow clone the bare hash.
VERSION="$(git describe --tags --dirty --always 2>/dev/null || echo "unknown")"

# CFBundleShortVersionString must be digits and dots only. Derive it from the
# nearest tag; with no tag there is no meaningful number, and a commit hash
# mangled into digits would be worse than admitting that.
if TAG="$(git describe --tags --abbrev=0 2>/dev/null)"; then
    SHORT_VERSION="$(printf '%s' "${TAG#v}" | sed -E 's/[^0-9.].*$//; s/\.+$//')"
fi
[[ -z "${SHORT_VERSION:-}" ]] && SHORT_VERSION="0.0.0"
DIST="./dist"
APP="$DIST/$APP_NAME.app"
INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

cd "$(dirname "$0")"

# --- tests ---------------------------------------------------------------
# swift test needs the XCTest/Testing runner, which ships with full Xcode.
# On a Command Line Tools-only box it can't run — warn and continue.
if xcrun --find xctest >/dev/null 2>&1; then
    echo "==> Running tests"
    swift test
else
    echo "==> WARNING: no Xcode test runner (Command Line Tools only) — skipping 'swift test'."
    echo "    Install Xcode and run 'swift test' to execute the unit tests."
fi

# --- release build -------------------------------------------------------
echo "==> Building release"
swift build -c release --product "$APP_NAME"
BIN="$(swift build -c release --product "$APP_NAME" --show-bin-path)/$APP_NAME"

# --- assemble bundle -----------------------------------------------------
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

ICON_KEY=""
if [[ -f assets/AppIcon.png ]]; then
    echo "==> Generating icon from assets/AppIcon.png"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512; do
        sips -z $size $size assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size*2)) $((size*2)) assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    $ICON_KEY
</dict>
</plist>
PLIST

# ad-hoc sign so SMAppService (launch at login) and Gatekeeper are happy locally
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
    echo "==> (codesign skipped — app still runs, launch-at-login may need a signed build)"

echo "==> Built $APP ($VERSION)"

if [[ $INSTALL -eq 1 ]]; then
    # A running app keeps executing from the old bundle even after it is
    # deleted, so without this it silently stays on the previous build.
    WAS_RUNNING=0
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        WAS_RUNNING=1
        echo "==> Quitting the running $APP_NAME"
        osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || pkill -x "$APP_NAME" || true
        for _ in $(seq 20); do
            pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
            sleep 0.25
        done
        pgrep -x "$APP_NAME" >/dev/null 2>&1 && pkill -9 -x "$APP_NAME" || true
    fi

    echo "==> Installing to /Applications"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"

    if [[ $WAS_RUNNING -eq 1 ]]; then
        echo "==> Relaunching $APP_NAME"
        open -a "/Applications/$APP_NAME.app"
    else
        echo "==> Installed. Launch from /Applications/$APP_NAME.app"
    fi
fi
