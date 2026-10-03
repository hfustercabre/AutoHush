#!/bin/bash
# Packages AutoHush.app into dist/AutoHush-<version>.dmg: a compressed
# disk image that opens as an installer window, with the app on the left, an
# arrow to an Applications shortcut on the right, and a note about the first
# launch (the app is not notarized).
#
# Usage: bash Scripts/build-dmg.sh [version]
# Environment:
#   SKIP_BUILD=1      package the existing AutoHush.app instead of rebuilding it
#   PLAIN_DMG=1       skip the window layout (no Finder scripting, e.g. on CI)
#   SIGNING_IDENTITY, SIGNING_KEYCHAIN, BUILD_NUMBER  passed through to build-app.sh
#
# The window layout is set by scripting Finder, so the first run asks for
# permission to control Finder. If that fails, a plain DMG is built instead.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

VERSION="${1:-$(plist_value "$INFO_PLIST" CFBundleShortVersionString)}"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

# Window geometry in points; icon centres must match Scripts/lib/dmg-background.swift.
WINDOW_WIDTH=640
WINDOW_HEIGHT=400
APP_ICON_POSITION="170, 190"
APPLICATIONS_POSITION="470, 190"
ICON_SIZE=112

if [[ "${SKIP_BUILD:-0}" != 1 ]]; then
    VERSION="$VERSION" bash "$PROJECT_DIR/Scripts/build-app.sh" release
fi
[[ -d "$APP_BUNDLE" ]] || fail "$APP_BUNDLE not found; build it first"
codesign --verify --strict "$APP_BUNDLE" || fail "$APP_BUNDLE is not validly signed"

step "Creating $(basename "$DMG_PATH")"
WORK="$(mktemp -d)"
DEVICE=""
cleanup() {
    [[ -n "$DEVICE" ]] && diskutil eject "$DEVICE" >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

STAGING="$WORK/$APP_NAME"
mkdir -p "$STAGING"
ditto "$APP_BUNDLE" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

styled=0
if [[ "${PLAIN_DMG:-0}" != 1 ]]; then
    note "drawing the window background"
    mkdir "$STAGING/.background"
    swift "$PROJECT_DIR/Scripts/lib/dmg-background.swift" "$WORK/background.png" 1
    swift "$PROJECT_DIR/Scripts/lib/dmg-background.swift" "$WORK/background@2x.png" 2
    tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" \
        -out "$STAGING/.background/background.tiff" >/dev/null 2>&1
    styled=1
fi

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
diskutil image create from --format UDZO --volumeName "$APP_NAME" "$STAGING" "$WORK/plain.dmg" >/dev/null 2>&1

# Lays out the Finder window of the volume mounted at $1. Finder saves the
# layout in the volume's .DS_Store, which travels with the image.
layout_window() {
    osascript - "$1" <<APPLESCRIPT
on run argv
    set volumePath to item 1 of argv
    tell application "Finder"
        set theVolume to disk (name of (info for (POSIX file volumePath as alias)))
        open theVolume
        set theWindow to container window of theVolume
        set current view of theWindow to icon view
        set toolbar visible of theWindow to false
        set statusbar visible of theWindow to false
        set sidebar width of theWindow to 0
        -- Bounds include the title bar; the content area is the background's size.
        set {leftEdge, topEdge} to {200, 120}
        set bounds of theWindow to {leftEdge, topEdge, leftEdge + $WINDOW_WIDTH, topEdge + $WINDOW_HEIGHT + 28}
        set viewOptions to icon view options of theWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $ICON_SIZE
        set text size of viewOptions to 13
        set label position of viewOptions to bottom
        set background picture of viewOptions to file ".background:background.tiff" of theVolume
        set position of item "$APP_NAME.app" of theVolume to {$APP_ICON_POSITION}
        set position of item "Applications" of theVolume to {$APPLICATIONS_POSITION}
        update theVolume without registering applications
        delay 1
        close theWindow
    end tell
end run
APPLESCRIPT
}

if [[ "$styled" == 1 ]]; then
    note "laying out the installer window (Finder may ask for permission)"
    # Changes go to a shadow file, then are folded into the final image.
    attach_output="$(diskutil image attach --shadow "$WORK/layout.shadow" "$WORK/plain.dmg")"
    DEVICE="$(awk 'NR == 1 { print $1 }' <<<"$attach_output")"
    MOUNT_POINT="$(grep -o '/Volumes/.*' <<<"$attach_output" | head -n 1)"
    if [[ -n "$MOUNT_POINT" ]] && layout_window "$MOUNT_POINT"; then
        sync
        diskutil eject "$DEVICE" >/dev/null
        DEVICE=""
        diskutil image create from --format UDZO --shadow "$WORK/layout.shadow" \
            "$WORK/plain.dmg" "$DMG_PATH" >/dev/null 2>&1
    else
        note "warning: could not lay out the window; building a plain DMG instead"
        styled=0
    fi
fi
if [[ "$styled" != 1 ]]; then
    [[ -n "$DEVICE" ]] && { diskutil eject "$DEVICE" >/dev/null 2>&1 || true; DEVICE=""; }
    mv "$WORK/plain.dmg" "$DMG_PATH"
fi

echo ""
echo "Done: $DMG_PATH"
