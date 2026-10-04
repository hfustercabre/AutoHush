#!/bin/bash
# Shared settings and helpers for the build and release scripts (sourced).

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="AutoHush"
BUNDLE_ID="com.autohush.AutoHush"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
DIST_DIR="$PROJECT_DIR/dist"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
ENTITLEMENTS="$PROJECT_DIR/Resources/$APP_NAME.entitlements"
# Icon Composer document; compiled into the app by Scripts/build-app.sh.
APP_ICON="$PROJECT_DIR/Resources/$APP_NAME.icon"
# String Catalogs: Localizable.xcstrings holds the app's text in every
# language, InfoPlist.xcstrings the Info.plist texts. Scripts/build-app.sh adds
# the strings the code uses to the first and compiles both into the app.
LOCALIZATION_DIR="$PROJECT_DIR/Resources/Localization"
STRING_CATALOG="$LOCALIZATION_DIR/Localizable.xcstrings"
# Created by Scripts/create-signing-certificate.sh.
SELF_SIGNED_IDENTITY="AutoHush Self-Signed"
# GitHub repository whose releases installed copies update from.
GITHUB_REPO="hfustercabre/AutoHush"
# Homebrew tap with the AutoHush cask; Scripts/update-tap.sh updates it.
TAP_REPO="hfustercabre/homebrew-tap"

step() { echo "==> $*"; }
note() { echo "    $*"; }
fail() { echo "error: $*" >&2; exit 1; }

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }

# Optional keychain holding the signing identity ($SIGNING_KEYCHAIN), e.g. on CI.
keychain_args() {
    if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
        echo "--keychain" "$SIGNING_KEYCHAIN"
    fi
}

has_identity() {
    # No -v: the self-signed certificate is valid for signing but not "trusted".
    security find-identity -p codesigning ${SIGNING_KEYCHAIN:+"$SIGNING_KEYCHAIN"} 2>/dev/null \
        | grep -qF "\"$1\""
}

# Code signing identity, in order of preference:
#   1. $SIGNING_IDENTITY ("-" forces ad-hoc signing)
#   2. the "AutoHush Self-Signed" certificate
#   3. ad hoc ("-")
# The app is identified by its certificate rather than its content hash only
# with a real identity, so only then do macOS privacy permissions (Automation,
# System Audio Recording) survive rebuilds and updates.
resolve_signing_identity() {
    if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
        echo "$SIGNING_IDENTITY"
    elif has_identity "$SELF_SIGNED_IDENTITY"; then
        echo "$SELF_SIGNED_IDENTITY"
    else
        echo "-"
    fi
}

# Signs the app bundle with the hardened runtime and its entitlements.
sign_app() {
    local identity="$1"
    # shellcheck disable=SC2046
    codesign --force --sign "$identity" $(keychain_args) --timestamp=none \
        --options runtime --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
}
