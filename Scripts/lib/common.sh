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
# language, InfoPlist.xcstrings the Info.plist texts, AppShortcuts.xcstrings
# the App Shortcuts' phrases. Scripts/build-app.sh adds the strings the code
# uses to the first and compiles all three into the app.
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

# The first "Apple Development" identity in the keychain, or nothing. Only
# trusted identities count (-v), so an expired certificate, or one whose Apple
# intermediate certificate is missing, is skipped.
apple_development_identity() {
    local identities
    identities="$(security find-identity -v -p codesigning ${SIGNING_KEYCHAIN:+"$SIGNING_KEYCHAIN"} 2>/dev/null)" || true
    sed -n 's/^[^"]*"\(Apple Development:[^"]*\)".*/\1/p' <<<"$identities" | sed -n 1p
}

# Code signing identity, in order of preference:
#   1. $SIGNING_IDENTITY ("-" forces ad-hoc signing)
#   2. the first "Apple Development" identity in the keychain
#   3. the "AutoHush Self-Signed" certificate
#   4. ad hoc ("-")
# The app is identified by its certificate rather than its content hash only
# with a real identity, so only then do macOS privacy permissions (Automation,
# System Audio Recording) survive rebuilds and updates. Only an app signed
# with a developer team (the Apple Development identity) can run its
# Shortcuts actions.
resolve_signing_identity() {
    local apple
    if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
        echo "$SIGNING_IDENTITY"
        return
    fi
    apple="$(apple_development_identity)"
    if [[ -n "$apple" ]]; then
        echo "$apple"
    elif has_identity "$SELF_SIGNED_IDENTITY"; then
        echo "$SELF_SIGNED_IDENTITY"
    else
        echo "-"
    fi
}

# The designated requirement for an identity issued by Apple: the app's
# identifier and the developer's team (the OU of the certificate's subject),
# not the certificate itself. A renewed certificate has another name and
# fingerprint but the same team, so permissions and self-updates carry over.
# Prints nothing for ad hoc ("-") and self-signed identities, and for a
# certificate that has no team: codesign's default requirement stays.
team_requirement() {
    local identity="$1" cert details team
    [[ "$identity" != "-" ]] || return 0
    cert="$(security find-certificate -c "$identity" -p ${SIGNING_KEYCHAIN:+"$SIGNING_KEYCHAIN"} 2>/dev/null)" || return 0
    details="$(openssl x509 -noout -subject -issuer -nameopt RFC2253 <<<"$cert" 2>/dev/null)" || return 0
    # "anchor apple generic" holds only for a certificate issued by Apple.
    grep -q '^issuer=.*O=Apple Inc' <<<"$details" || return 0
    team="$(sed -n 's/^subject=\(.*,\)\{0,1\}OU=\([A-Za-z0-9]*\).*/\2/p' <<<"$details")"
    [[ -n "$team" ]] || return 0
    echo "designated => identifier \"$BUNDLE_ID\" and anchor apple generic and certificate leaf[subject.OU] = \"$team\""
}

# Signs the app bundle with the hardened runtime and its entitlements, under
# the team requirement when the identity has one.
sign_app() {
    local identity="$1" requirement
    local args=(--force --sign "$identity" --timestamp=none
        --options runtime --entitlements "$ENTITLEMENTS")
    requirement="$(team_requirement "$identity")"
    if [[ -n "$requirement" ]]; then
        # codesign reads text after "=" as the requirement itself, not a file.
        args+=("-r=$requirement")
    fi
    # shellcheck disable=SC2046
    codesign "${args[@]}" $(keychain_args) "$APP_BUNDLE"
}
