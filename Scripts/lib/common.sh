#!/bin/bash
# Shared settings and helpers for the build and release scripts (sourced).

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="AutoHush"
BUNDLE_ID="com.autohush.AutoHush"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
DIST_DIR="$PROJECT_DIR/dist"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
ENTITLEMENTS="$PROJECT_DIR/Resources/$APP_NAME.entitlements"
# Created by Scripts/create-signing-certificate.sh.
SELF_SIGNED_IDENTITY="AutoHush Self-Signed"

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
