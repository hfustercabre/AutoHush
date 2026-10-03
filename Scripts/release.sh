#!/bin/bash
# Prepares a release of AutoHush. Nothing is published, committed or tagged.
#
# Usage: bash Scripts/release.sh <version>        e.g. bash Scripts/release.sh 0.3.0
#
# Steps:
#   1. sets the version in Resources/Info.plist (build number + 1) and turns
#      CHANGELOG.md's [Unreleased] section into [<version>] — <date>
#   2. runs the test suite
#   3. builds the app, signed with the AutoHush certificate (hardened runtime)
#   4. packages dist/AutoHush-<version>.dmg
#   5. writes the DMG's SHA-256 into Casks/autohush.rb and the release
#      notes into dist/release-notes-<version>.md
#
# Releases must be signed with the same certificate every time, so users keep
# their permissions when they update; ad-hoc releases are refused.
#
# Environment: SIGNING_IDENTITY, SIGNING_KEYCHAIN (see Scripts/lib/common.sh),
#              ALLOW_DIRTY=1 to skip the clean-working-tree check.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "usage: release.sh <major.minor.patch>"
TAG="v$VERSION"
CHANGELOG="$PROJECT_DIR/CHANGELOG.md"
CASK="$PROJECT_DIR/Casks/autohush.rb"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
NOTES_PATH="$DIST_DIR/release-notes-$VERSION.md"

cd "$PROJECT_DIR"
if [[ "${ALLOW_DIRTY:-0}" != 1 && -n "$(git status --porcelain)" ]]; then
    fail "working tree has uncommitted changes (commit them or set ALLOW_DIRTY=1)"
fi
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "tag $TAG already exists"
grep -q '^## \[Unreleased\]' "$CHANGELOG" || fail "CHANGELOG.md has no [Unreleased] section"
IDENTITY="$(resolve_signing_identity)"
[[ "$IDENTITY" != "-" ]] || fail "no signing certificate: run Scripts/create-signing-certificate.sh (or restore your backup) first"

# 1. Version and changelog ---------------------------------------------------
BUILD_NUMBER=$(( $(plist_value "$INFO_PLIST" CFBundleVersion) + 1 ))
step "Setting version $VERSION ($BUILD_NUMBER)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
sed -i '' "s/^## \[Unreleased\]$/## [$VERSION] — $(date +%Y-%m-%d)/" "$CHANGELOG"

# 2. Tests -------------------------------------------------------------------
step "Running tests"
swift test >/dev/null || fail "tests failed; release aborted (version files were already updated)"

# 3–4. App and disk image -----------------------------------------------------
SIGNING_IDENTITY="$IDENTITY" bash "$PROJECT_DIR/Scripts/build-dmg.sh" "$VERSION"

# 5. Cask and release notes ----------------------------------------------------
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{ print $1 }')"
step "Updating Casks/autohush.rb"
sed -i '' -E \
    -e "s/^  version \".*\"$/  version \"$VERSION\"/" \
    -e "s/^  sha256 .*$/  sha256 \"$SHA256\"/" \
    "$CASK"
awk -v heading="## [$VERSION]" '
    index($0, heading) == 1 { found = 1; next }
    found && (/^## \[/ || /^---$/) { exit }
    found { print }
' "$CHANGELOG" | sed -e '/./,$!d' > "$NOTES_PATH"

echo ""
echo "Release $VERSION prepared:"
echo "  disk image     $DMG_PATH"
echo "  SHA-256        $SHA256"
echo "  signed with    $IDENTITY (not notarized: Gatekeeper asks users to confirm the first launch)"
echo "  release notes  $NOTES_PATH"
echo ""
echo "Next steps (not done by this script):"
echo "  git add Resources/Info.plist CHANGELOG.md Casks/autohush.rb"
echo "  git commit -m \"release: $VERSION\" && git tag $TAG"
echo "  git push origin main $TAG"
echo "  Create the GitHub release $TAG, upload $(basename "$DMG_PATH") and paste the release notes."
