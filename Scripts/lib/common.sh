#!/bin/bash
# Shared settings and helpers for the build and release scripts (sourced).
# The settings are used by the scripts that source this file, not here:
# shellcheck disable=SC2034

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
# The developer team every release is signed by. Installed copies accept an
# update only from it (their designated requirement names it): it never changes.
RELEASE_TEAM="BNT2VN4LH5"

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

# The "Apple Development" identity to sign with, by its SHA-1 hash, or
# nothing. Only trusted identities count (-v), so an expired certificate, or
# one whose Apple intermediate certificate is missing, is skipped. One of
# $RELEASE_TEAM comes before any other team's; of several (a renewed
# certificate beside the old one), the one valid longest: they share a name,
# which codesign refuses as ambiguous.
apple_development_identity() {
    local identities hash end rank best="" best_rank=-1 best_end=0
    identities="$(security find-identity -v -p codesigning ${SIGNING_KEYCHAIN:+"$SIGNING_KEYCHAIN"} 2>/dev/null)" || true
    while read -r hash; do
        end="$(certificate_pem "$hash" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
        end="$(date -j -u -f "%b %e %H:%M:%S %Y %Z" "$end" +%s 2>/dev/null)" || continue
        rank=0
        [[ "$(identity_team "$hash")" == "$RELEASE_TEAM" ]] && rank=1
        if (( rank > best_rank || (rank == best_rank && end > best_end) )); then
            best="$hash"
            best_rank="$rank"
            best_end="$end"
        fi
    done < <(sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "Apple Development:.*/\1/p' <<<"$identities")
    echo "$best"
}

# The PEM certificate of an identity: its SHA-1 hash, or its name.
certificate_pem() {
    local identity="$1"
    if [[ "$identity" =~ ^[0-9A-F]{40}$ ]]; then
        security find-certificate -a -Z -p ${SIGNING_KEYCHAIN:+"$SIGNING_KEYCHAIN"} 2>/dev/null \
            | awk -v hash="$identity" '/^SHA-1 hash:/ { mine = ($3 == hash) } mine { print } mine && /END CERTIFICATE/ { exit }' \
            | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p'
    else
        security find-certificate -c "$identity" -p ${SIGNING_KEYCHAIN:+"$SIGNING_KEYCHAIN"} 2>/dev/null
    fi
}

# An identity's name, for messages: its own name when given by SHA-1 hash.
identity_name() {
    local name
    name="$(security find-identity -v -p codesigning ${SIGNING_KEYCHAIN:+"$SIGNING_KEYCHAIN"} 2>/dev/null \
        | sed -n "s/^ *[0-9]*) $1 \"\([^\"]*\)\".*/\1/p" | sed -n 1p)"
    echo "${name:-$1}"
}

# Code signing identity, in order of preference:
#   1. $SIGNING_IDENTITY ("-" forces ad-hoc signing)
#   2. the keychain's "Apple Development" identity (the one valid longest)
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

# The developer team of an identity issued by Apple (the OU of its
# certificate's subject); nothing for ad hoc ("-"), self-signed identities
# and a certificate without a team.
identity_team() {
    local identity="$1" cert details
    [[ "$identity" != "-" ]] || return 0
    cert="$(certificate_pem "$identity")"
    [[ -n "$cert" ]] || return 0
    details="$(openssl x509 -noout -subject -issuer -nameopt RFC2253 <<<"$cert" 2>/dev/null)" || return 0
    # "anchor apple generic" holds only for a certificate issued by Apple.
    grep -q '^issuer=.*O=Apple Inc' <<<"$details" || return 0
    sed -n 's/^subject=\(.*,\)\{0,1\}OU=\([A-Za-z0-9]*\).*/\2/p' <<<"$details"
}

# The designated requirement for an identity issued by Apple: the app's
# identifier and the developer's team, not the certificate itself. A renewed
# certificate has another name and fingerprint but the same team, so
# permissions and self-updates carry over. Prints nothing for an identity
# without a team (see identity_team): codesign's default requirement stays.
team_requirement() {
    local team identifier="${2:-$BUNDLE_ID}"
    team="$(identity_team "$1")"
    [[ -n "$team" ]] || return 0
    echo "designated => identifier \"$identifier\" and anchor apple generic and certificate leaf[subject.OU] = \"$team\""
}

# Signs the app bundle (or a helper inside it, given its path) with the
# hardened runtime and the app's entitlements, under the team requirement
# when the identity has one.
sign_app() {
    local identity="$1" target="${2:-$APP_BUNDLE}" identifier="$BUNDLE_ID" requirement
    local args=(--force --sign "$identity" --timestamp=none
        --options runtime --entitlements "$ENTITLEMENTS")
    # A helper inside the app gets an identifier under the app's.
    if [[ "$target" != "$APP_BUNDLE" ]]; then
        identifier="$BUNDLE_ID.$(basename "$target")"
        args+=(--identifier "$identifier")
    fi
    requirement="$(team_requirement "$identity" "$identifier")"
    if [[ -n "$requirement" ]]; then
        # codesign reads text after "=" as the requirement itself, not a file.
        args+=("-r=$requirement")
    fi
    # shellcheck disable=SC2046
    codesign "${args[@]}" $(keychain_args) "$target"
}
