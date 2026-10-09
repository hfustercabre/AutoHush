#!/bin/bash
# Points the Homebrew tap at a published release, so that
# `brew install --cask hfustercabre/tap/autohush` installs it.
#
# Usage: bash Scripts/update-tap.sh <version>     e.g. bash Scripts/update-tap.sh 0.3.4
#
# Run it after the GitHub release is published, so the tap never points at a
# download that isn't there yet.
#
# Steps:
#   1. downloads the release's DMG from GitHub and checks it is the one that
#      Scripts/release.sh built in dist/
#   2. clones the tap into a temporary folder and writes the version and the
#      DMG's SHA-256 into Casks/autohush.rb
#   3. commits "autohush <version>" and pushes it
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "usage: update-tap.sh <major.minor.patch>"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_URL="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$DMG_NAME"
[[ -f "$DMG_PATH" ]] || fail "$DMG_PATH not found: run Scripts/release.sh $VERSION first"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR:?}"' EXIT

# 1. Published disk image ----------------------------------------------------
step "Checking the published $DMG_NAME"
curl -fsSL -o "$WORK_DIR/$DMG_NAME" "$DMG_URL" \
    || fail "couldn't download $DMG_URL: publish the GitHub release first"
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{ print $1 }')"
[[ "$(shasum -a 256 "$WORK_DIR/$DMG_NAME" | awk '{ print $1 }')" == "$SHA256" ]] \
    || fail "the published $DMG_NAME differs from $DMG_PATH"

# 2. Cask --------------------------------------------------------------------
step "Updating Casks/autohush.rb in $TAP_REPO"
TAP_DIR="$WORK_DIR/tap"
CASK="$TAP_DIR/Casks/autohush.rb"
git clone -q --depth 1 "https://github.com/$TAP_REPO.git" "$TAP_DIR"
sed -i '' -E \
    -e "s/^  version \".*\"$/  version \"$VERSION\"/" \
    -e "s/^  sha256 .*$/  sha256 \"$SHA256\"/" \
    "$CASK"
grep -q "^  version \"$VERSION\"$" "$CASK" && grep -q "^  sha256 \"$SHA256\"$" "$CASK" \
    || fail "couldn't set the version and sha256 in Casks/autohush.rb"
if git -C "$TAP_DIR" diff --quiet; then
    note "The tap already points at $VERSION."
    exit 0
fi

# 3. Publish -----------------------------------------------------------------
# Commit as the author configured for this repository.
step "Publishing autohush $VERSION"
git -C "$TAP_DIR" \
    -c user.name="$(git -C "$PROJECT_DIR" config user.name)" \
    -c user.email="$(git -C "$PROJECT_DIR" config user.email)" \
    commit -q -am "autohush $VERSION"
git -C "$TAP_DIR" push -q origin HEAD

echo ""
echo "Tap updated: brew install --cask ${TAP_REPO/homebrew-/}/autohush installs $VERSION."
