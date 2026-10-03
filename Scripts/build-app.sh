#!/bin/bash
# Builds AutoHush.app and signs it with the hardened runtime.
#
# Usage: bash Scripts/build-app.sh [release|debug]
# Environment:
#   SIGNING_IDENTITY  identity to sign with (see Scripts/lib/common.sh); "-" = ad hoc
#   SIGNING_KEYCHAIN  keychain that holds the identity (default: the keychain search list)
#   VERSION           CFBundleShortVersionString for this bundle (default: Resources/Info.plist)
#   BUILD_NUMBER      CFBundleVersion for this bundle (default: Resources/Info.plist)
#   KEEP_PERMISSIONS=1  skip the privacy-permission reset of ad-hoc builds
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

BUILD_CONFIG="${1:-release}"
case "$BUILD_CONFIG" in
    release) PRODUCTS_DIR="$PROJECT_DIR/.build/out/Products/Release" ;;
    debug)   PRODUCTS_DIR="$PROJECT_DIR/.build/out/Products/Debug" ;;
    *)       fail "unknown configuration '$BUILD_CONFIG' (use release or debug)" ;;
esac

step "Building $BUILD_CONFIG"
cd "$PROJECT_DIR"
HOME=/tmp SWIFTPM_CONFIG_HOME=/tmp/swiftpm CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    swift build -c "$BUILD_CONFIG" --scratch-path .build --product "$APP_NAME"

step "Assembling $APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$PRODUCTS_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
fi
note "version $(plist_value "$APP_BUNDLE/Contents/Info.plist" CFBundleShortVersionString)" \
     "($(plist_value "$APP_BUNDLE/Contents/Info.plist" CFBundleVersion))"

# The icon follows the light, dark, clear and tinted appearances on macOS 26
# and later (Assets.car); older systems get the flat AutoHush.icns. Info.plist
# names both. actool comes with Xcode.
step "Compiling the app icon"
if xcrun --find actool >/dev/null 2>&1; then
    ICON_INFO="$(mktemp)"
    if ! ICON_LOG="$(xcrun actool "$APP_ICON" --compile "$APP_BUNDLE/Contents/Resources" \
            --platform macosx --minimum-deployment-target "$(plist_value "$INFO_PLIST" LSMinimumSystemVersion)" \
            --app-icon "$APP_NAME" --output-partial-info-plist "$ICON_INFO" \
            --output-format human-readable-text 2>&1)"; then
        echo "$ICON_LOG" >&2
        fail "actool could not compile $APP_ICON"
    fi
    rm -f "$ICON_INFO"
else
    note "warning: actool not found (it comes with Xcode); the app keeps the generic icon"
fi

IDENTITY="$(resolve_signing_identity)"
if [[ "$IDENTITY" == "-" ]]; then
    step "Signing ad hoc (hardened runtime)"
else
    step "Signing with \"$IDENTITY\" (hardened runtime)"
fi
sign_app "$IDENTITY"
codesign --verify --strict "$APP_BUNDLE"

if [[ "$IDENTITY" == "-" && "${KEEP_PERMISSIONS:-0}" != 1 ]]; then
    # macOS treats every ad-hoc build as a new app: drop the previous build's
    # permission entries so it prompts again instead of failing silently.
    step "Resetting privacy permissions (ad-hoc build)"
    tccutil reset AppleEvents "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset AudioCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
    note "Run Scripts/create-signing-certificate.sh once to keep permissions across builds."
fi

echo ""
echo "Done: $APP_BUNDLE"
