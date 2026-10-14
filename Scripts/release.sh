#!/bin/bash
# Prepares a release of AutoHush. Nothing is published, committed or tagged.
#
# Usage: bash Scripts/release.sh <version>        e.g. bash Scripts/release.sh 0.3.0
#
# Steps:
#   1. runs the test suite, before anything changes
#   2. builds the app with the new version (build number + 1), signed with
#      the maintainer's Apple Development certificate under the developer
#      team's requirement (hardened runtime), and packages
#      dist/AutoHush-<version>.dmg
#   3. only then sets the version in Resources/Info.plist and turns
#      CHANGELOG.md's [Unreleased] section into [<version>] — <date>, so a
#      failed build leaves both as they were
#   4. writes the release notes into dist/release-notes-<version>.md
#
# Once the GitHub release is published, Scripts/update-tap.sh points the
# Homebrew tap at it.
#
# Releases must be signed by the same developer team every time, so installed
# copies accept the update and users keep their permissions; ad hoc and
# self-signed releases are refused.
#
# Environment: SIGNING_IDENTITY, SIGNING_KEYCHAIN (see Scripts/lib/common.sh),
#              ALLOW_DIRTY=1 to skip the clean-working-tree check.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "usage: release.sh <major.minor.patch>"
TAG="v$VERSION"
CHANGELOG="$PROJECT_DIR/CHANGELOG.md"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
NOTES_PATH="$DIST_DIR/release-notes-$VERSION.md"

cd "$PROJECT_DIR"
if [[ "${ALLOW_DIRTY:-0}" != 1 && -n "$(git status --porcelain)" ]]; then
    fail "working tree has uncommitted changes (commit them or set ALLOW_DIRTY=1)"
fi
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "tag $TAG already exists"
grep -q '^## \[Unreleased\]' "$CHANGELOG" || fail "CHANGELOG.md has no [Unreleased] section"
IDENTITY="$(resolve_signing_identity)"
# Installed copies accept an update only if it satisfies their designated
# requirement, which names the developer team. Only an identity issued by Apple
# with a team has one: not ad hoc, self-signed or any other certificate.
if [[ -z "$(team_requirement "$IDENTITY")" ]]; then
    if [[ "$IDENTITY" == "-" ]]; then
        found="the identity is ad hoc (no valid Apple Development certificate was found or selected)"
    else
        found="\"$IDENTITY\" has no developer team"
    fi
    fail "releases must be signed with the maintainer's Apple Development certificate (its developer team), but $found; installed copies would refuse the update. If the certificate expired, renew it in Xcode (Settings → Accounts → Manage Certificates)."
fi

# 1. Tests -------------------------------------------------------------------
step "Running tests"
# Every test, the slow ones too, even where quick runs are the default.
env -u AUTOHUSH_QUICK_TESTS swift test >/dev/null || fail "tests failed; release aborted (nothing was changed)"

# 2. App and disk image -------------------------------------------------------
# The bundle gets the new version and build number (build-app.sh sets them in
# its own Info.plist); Resources/Info.plist and the CHANGELOG change only
# once it's built.
BUILD_NUMBER=$(( $(plist_value "$INFO_PLIST" CFBundleVersion) + 1 ))
SIGNING_IDENTITY="$IDENTITY" BUILD_NUMBER="$BUILD_NUMBER" bash "$PROJECT_DIR/Scripts/build-dmg.sh" "$VERSION"

# 3. Version and changelog ---------------------------------------------------
step "Setting version $VERSION ($BUILD_NUMBER)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
sed -i '' "s/^## \[Unreleased\]$/## [$VERSION] — $(date +%Y-%m-%d)/" "$CHANGELOG"

# 4. Release notes -----------------------------------------------------------
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{ print $1 }')"
# The team the built app is signed with, so an identity from the wrong
# keychain shows before anything is published.
TEAM="$(codesign -dv "$APP_BUNDLE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
step "Writing the release notes"
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
echo "  developer team ${TEAM:-none} (must be the last release's)"
echo "  release notes  $NOTES_PATH"
echo ""
echo "Next steps (not done by this script):"
echo "  git add Resources/Info.plist CHANGELOG.md"
echo "  git commit -m \"release: $VERSION\" && git tag $TAG       (on wip)"
echo "  git switch main && git merge --ff-only wip && git switch wip"
echo "  git push origin wip main $TAG"
echo "  Create the GitHub release $TAG, upload $(basename "$DMG_PATH") and paste the release notes."
echo "  bash Scripts/update-tap.sh $VERSION   (points the Homebrew tap at the published release)"
