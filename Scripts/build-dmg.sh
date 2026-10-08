#!/bin/bash
# Packages AutoHush.app into dist/AutoHush-<version>.dmg: a compressed
# disk image that opens as an installer window, with the app on the left, an
# arrow to an Applications shortcut on the right, and a note about the first
# launch (the app is not notarized). The mounted disk shows the app's icon.
#
# Usage: bash Scripts/build-dmg.sh [version]
# Environment:
#   SKIP_BUILD=1      package the existing AutoHush.app instead of rebuilding it
#   PYTHON            the Python (3.10 or later) for dmgbuild, if python3 is older
#   SIGNING_IDENTITY, SIGNING_KEYCHAIN, BUILD_NUMBER  passed through to build-app.sh
#
# dmgbuild (https://github.com/dmgbuild/dmgbuild) builds the image and writes
# its window layout (Scripts/lib/dmg-settings.py) without Finder. It's
# installed on first use into .build/, pinned by Scripts/lib/dmgbuild-requirements.txt.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

VERSION="${1:-$(plist_value "$INFO_PLIST" CFBundleShortVersionString)}"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

# The window's layout, icon places included, is in Scripts/lib/dmg-settings.py.
DMG_SETTINGS="$PROJECT_DIR/Scripts/lib/dmg-settings.py"
DMGBUILD_REQUIREMENTS="$PROJECT_DIR/Scripts/lib/dmgbuild-requirements.txt"

# Prints the path of dmgbuild, installing it first if needed: into a Python
# environment of its own in .build/, from the pinned, hash-checked files.
dmgbuild_tool() {
    local venv="$PROJECT_DIR/.build/dmgbuild-$(shasum -a 256 "$DMGBUILD_REQUIREMENTS" | cut -c1-12)"
    if [[ ! -x "$venv/bin/dmgbuild" ]]; then
        local python="" candidate
        for candidate in "${PYTHON:-}" python3 /opt/homebrew/bin/python3; do
            [[ -n "$candidate" ]] && command -v "$candidate" >/dev/null || continue
            "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null && { python="$candidate"; break; }
        done
        [[ -n "$python" ]] || fail "dmgbuild needs Python 3.10 or later: install one, or set PYTHON"
        note "installing dmgbuild into $(basename "$venv")" >&2
        rm -rf "${venv:?}"
        "$python" -m venv "$venv" >&2 &&
            "$venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes \
                -r "$DMGBUILD_REQUIREMENTS" >&2 ||
            fail "couldn't install dmgbuild"
    fi
    echo "$venv/bin/dmgbuild"
}

if [[ "${SKIP_BUILD:-0}" != 1 ]]; then
    VERSION="$VERSION" bash "$PROJECT_DIR/Scripts/build-app.sh" release
fi
[[ -d "$APP_BUNDLE" ]] || fail "$APP_BUNDLE not found; build it first"
codesign --verify --strict "$APP_BUNDLE" || fail "$APP_BUNDLE is not validly signed"

step "Creating $(basename "$DMG_PATH")"
DMGBUILD="$(dmgbuild_tool)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT

note "drawing the window background"
# Built with the app's menu bar icon, which the background shows.
swiftc -O -parse-as-library "$PROJECT_DIR/Sources/AutoHushApp/MenuBar/MenuBarIcon.swift" \
    "$PROJECT_DIR/Scripts/lib/dmg-background.swift" -o "$WORK/dmg-background"
"$WORK/dmg-background" "$WORK/background.png" 1
"$WORK/dmg-background" "$WORK/background@2x.png" 2
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" \
    -out "$WORK/background.tiff" >/dev/null 2>&1

note "building the image and laying out its window"
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
volume_icon="$APP_BUNDLE/Contents/Resources/$APP_NAME.icns"
[[ -f "$volume_icon" ]] || volume_icon=""
# dmgbuild drives hdiutil, which newer macOS calls deprecated on every use.
"$DMGBUILD" -s "$DMG_SETTINGS" -D app="$APP_BUNDLE" -D background="$WORK/background.tiff" \
    -D icon="$volume_icon" "$APP_NAME" "$DMG_PATH" >/dev/null 2> >(grep -v "is deprecated" >&2) ||
    fail "dmgbuild couldn't build $(basename "$DMG_PATH")"

echo ""
echo "Done: $DMG_PATH"
