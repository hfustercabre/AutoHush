#!/bin/bash
# Prepares a release of AutoHush. Nothing is published, committed or tagged.
#
# Usage: bash Scripts/release.sh <version>        e.g. bash Scripts/release.sh 0.3.0
#        bash Scripts/release.sh <version> --rc   a release candidate, on stg
#
# A release candidate (rc.1, rc.2… counted from the tags) is built the same
# way, as dist/AutoHush-<version>-rc.<n>.dmg with its notes from
# [Unreleased]; Resources/Info.plist and the CHANGELOG don't change, and its
# app carries its number (AutoHushReleaseCandidate). It's published as a
# GitHub pre-release, which only copies with Get release candidates on are
# offered: the others ask GitHub for the latest release, never a pre-release.
#
# Steps:
#   1. builds the app with the new version (build number + 1), signed with
#      the maintainer's Apple Development certificate under the developer
#      team's requirement (hardened runtime), and packages
#      dist/AutoHush-<version>.dmg
#   2. only then sets the version in Resources/Info.plist and turns
#      CHANGELOG.md's [Unreleased] section into [<version>] — <date>, so a
#      failed build leaves both as they were
#   3. writes the release notes into dist/release-notes-<version>.md
#
# It runs no tests: the release checklist runs all of them, the slow ones
# too, in a VM before this.
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
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && ( $# -eq 1 || ( $# -eq 2 && "${2:-}" == --rc ) ) ]] ||
    fail "usage: release.sh <major.minor.patch> [--rc]"
RC=0
[[ "${2:-}" == --rc ]] && RC=1
TAG="v$VERSION"
CHANGELOG="$PROJECT_DIR/CHANGELOG.md"

cd "$PROJECT_DIR"
# The branch being released (release/vX, or a hotfix/ branch), named in the
# next steps printed at the end.
BRANCH="$(git branch --show-current)"
if [[ "${ALLOW_DIRTY:-0}" != 1 && -n "$(git status --porcelain)" ]]; then
    fail "working tree has uncommitted changes (commit them or set ALLOW_DIRTY=1)"
fi
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "tag $TAG already exists"
grep -q '^## \[Unreleased\]' "$CHANGELOG" || fail "CHANGELOG.md has no [Unreleased] section"
# What's built: the version, or its next release candidate (the tags pushed
# by now counted too), made only on stg.
if (( RC )); then
    [[ "$BRANCH" == stg ]] || fail "a release candidate is made on stg, not on ${BRANCH:-a detached HEAD}"
    git fetch -q origin --tags || fail "couldn't read the tags on origin, which number the release candidates"
    RC=1
    while git rev-parse -q --verify "refs/tags/$TAG-rc.$RC" >/dev/null; do RC=$(( RC + 1 )); done
    LABEL="$VERSION-rc.$RC"
else
    LABEL="$VERSION"
fi
DMG_PATH="$DIST_DIR/$APP_NAME-$LABEL.dmg"
NOTES_PATH="$DIST_DIR/release-notes-$LABEL.md"
IDENTITY="$(resolve_signing_identity)"
# Installed copies accept an update only if it satisfies their designated
# requirement, which names the developer team. Only an identity issued by Apple
# to that team has one: not ad hoc, self-signed, another team's or any other
# certificate.
IDENTITY_TEAM="$(identity_team "$IDENTITY")"
if [[ "$IDENTITY_TEAM" != "$RELEASE_TEAM" ]]; then
    if [[ "$IDENTITY" == "-" ]]; then
        found="the identity is ad hoc (no valid Apple Development certificate was found or selected)"
    elif [[ -z "$IDENTITY_TEAM" ]]; then
        found="\"$(identity_name "$IDENTITY")\" has no developer team"
    else
        found="\"$(identity_name "$IDENTITY")\" is team $IDENTITY_TEAM's, not $RELEASE_TEAM's"
    fi
    fail "releases must be signed with the maintainer's Apple Development certificate (its developer team), but $found; installed copies would refuse the update. If the certificate expired, renew it in Xcode (Settings → Accounts → Manage Certificates)."
fi

# 1. App and disk image -------------------------------------------------------
# The bundle gets the new version and build number (build-app.sh sets them in
# its own Info.plist); Resources/Info.plist and the CHANGELOG change only
# once it's built.
BUILD_NUMBER=$(( $(plist_value "$INFO_PLIST" CFBundleVersion) + 1 ))
# A release candidate's app says which it is (AutoHushReleaseCandidate), so
# its updater offers the release that follows it.
CANDIDATE=""
(( RC )) && CANDIDATE="$RC"
SIGNING_IDENTITY="$IDENTITY" BUILD_NUMBER="$BUILD_NUMBER" RELEASE_CANDIDATE="$CANDIDATE" KEEP_SYMBOLS=1 \
    bash "$PROJECT_DIR/Scripts/build-dmg.sh" "$VERSION"
# A release candidate's app is the version itself; only its image says which.
(( RC )) && mv -f "$DIST_DIR/$APP_NAME-$VERSION.dmg" "$DMG_PATH"
# The team the built app is signed with: anything but $RELEASE_TEAM stops the
# release here, before the version and the CHANGELOG change.
TEAM="$(codesign -dv "$APP_BUNDLE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ "$TEAM" == "$RELEASE_TEAM" ]] || fail "the app is signed by team ${TEAM:-none}, not $RELEASE_TEAM: installed copies would refuse the update"

# 2. Version and changelog ---------------------------------------------------
if (( ! RC )); then
    step "Setting version $VERSION ($BUILD_NUMBER)"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
    sed -i '' "s/^## \[Unreleased\]$/## [$VERSION] — $(date +%Y-%m-%d)/" "$CHANGELOG"
fi

# 3. Release notes -----------------------------------------------------------
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{ print $1 }')"
step "Writing the release notes"
if (( RC )); then
    heading="## [Unreleased]"
    printf '%s\n\n' "Release candidate $RC of AutoHush $VERSION, for testing before its release. Only copies with Get release candidates on (Settings → About) are offered it, and Homebrew doesn't install it." > "$NOTES_PATH"
else
    heading="## [$VERSION]"
    : > "$NOTES_PATH"
fi
awk -v heading="$heading" '
    index($0, heading) == 1 { found = 1; next }
    found && (/^## \[/ || /^---$/) { exit }
    found { print }
' "$CHANGELOG" | sed -e '/./,$!d' >> "$NOTES_PATH"

echo ""
if (( RC )); then
    echo "Release candidate $LABEL prepared:"
else
    echo "Release $VERSION prepared:"
fi
echo "  disk image     $DMG_PATH"
echo "  SHA-256        $SHA256"
echo "  signed with    $(identity_name "$IDENTITY") (not notarized: Gatekeeper asks users to confirm the first launch)"
echo "  developer team $TEAM"
echo "  release notes  $NOTES_PATH"
echo ""
echo "Next steps (not done by this script):"
if (( RC )); then
    echo "  git tag -a v$LABEL -m \"AutoHush $VERSION RC $RC\" && git push origin v$LABEL   (stg's commit, once CI passed on it)"
    echo "  gh release create v$LABEL $DMG_PATH --verify-tag --prerelease --title v$LABEL --notes-file $NOTES_PATH"
    echo "  No Homebrew: the tap follows releases only."
else
    echo "  git add Resources/Info.plist CHANGELOG.md"
    echo "  git commit -m \"release: $VERSION\" && git tag -a $TAG -m \"AutoHush $VERSION\"   (on release/$TAG, or the hotfix/ branch)"
    echo "  git switch main && git merge --ff-only $BRANCH; git switch stg && git merge --ff-only $BRANCH; git switch dev && git merge --ff-only $BRANCH   (a hotfix: git merge it into stg and dev)"
    echo "  git push origin dev stg main $TAG; git branch -d $BRANCH   (and git push origin --delete $BRANCH if it was pushed)"
    echo "  Create the GitHub release $TAG (titled $TAG), upload $(basename "$DMG_PATH") and paste the release notes."
    echo "  bash Scripts/update-tap.sh $VERSION   (points the Homebrew tap at the published release)"
fi
