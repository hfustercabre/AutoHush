#!/bin/bash
# Builds AutoHush.app and signs it with the hardened runtime.
#
# Usage: bash Scripts/build-app.sh [release|debug]
# Environment:
#   SIGNING_IDENTITY  identity to sign with (see Scripts/lib/common.sh); "-" = ad hoc
#   SIGNING_KEYCHAIN  keychain that holds the identity (default: the keychain search list)
#   VERSION           CFBundleShortVersionString for this bundle (default: Resources/Info.plist)
#   BUILD_NUMBER      CFBundleVersion for this bundle (default: Resources/Info.plist)
#   RELEASE_CANDIDATE n: the bundle is release candidate n of VERSION
#                     (AutoHushReleaseCandidate, which the app's updater reads)
#   KEEP_PERMISSIONS=1  skip the privacy-permission reset of ad-hoc builds
#   KEEP_SYMBOLS=1    keep a release's symbols in dist/dSYMs (release.sh sets it)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

BUILD_CONFIG="${1:-release}"
# A release runs on Apple silicon and Intel Macs alike (macOS 14.4 to 26 still
# run on Intel); a debug build only on this Mac's kind.
case "$BUILD_CONFIG" in
    release) CONFIG_DIR=Release; ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
    debug)   CONFIG_DIR=Debug; ARCH_FLAGS=() ;;
    *)       fail "unknown configuration '$BUILD_CONFIG' (use release or debug)" ;;
esac
PRODUCTS_DIR="$PROJECT_DIR/.build/out/Products/$CONFIG_DIR"
# The helper Add an App… runs the check in, inside the app.
HELPER_NAME=playercheck
HELPER="$APP_BUNDLE/Contents/Helpers/$HELPER_NAME"
# Where the compiler lists each source file's localizable strings.
STRINGS_DIR="$PROJECT_DIR/.build/localized-strings/$BUILD_CONFIG"

step "Building $BUILD_CONFIG"
cd "$PROJECT_DIR"
# The app, then the helper Add an App… runs the check in (Sources/PlayerCheck),
# with the same flags, so the second build only compiles the helper's own code.
for product in "$APP_NAME" "$HELPER_NAME"; do
    HOME=/tmp SWIFTPM_CONFIG_HOME=/tmp/swiftpm CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
        swift build -c "$BUILD_CONFIG" --scratch-path .build --product "$product" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} \
            -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$STRINGS_DIR"
done

step "Assembling $APP_NAME.app"
rm -rf "${APP_BUNDLE:?}"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Helpers"
cp "$PRODUCTS_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PRODUCTS_DIR/$HELPER_NAME" "$HELPER"
if [[ "$BUILD_CONFIG" == release ]]; then
    for binary in "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$HELPER"; do
        ARCHS=" $(lipo -archs "$binary") "
        [[ "$ARCHS" == *" arm64 "* && "$ARCHS" == *" x86_64 "* ]] \
            || fail "the release build of $(basename "$binary") isn't for both Apple silicon and Intel (it's for:$ARCHS)"
    done
fi
# SwiftPM's build system records the oldest macOS the app runs on as the SDK
# it was built with, and macOS 26 and later then draw it the old way, without
# Liquid Glass. Record the SDK it was really built with; older systems ignore
# it. Signing comes after.
MIN_MACOS="$(plist_value "$INFO_PLIST" LSMinimumSystemVersion)"
SDK_VERSION="$(xcrun --show-sdk-version)"
for binary in "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$HELPER"; do
    xcrun vtool -set-build-version macos "$MIN_MACOS" "$SDK_VERSION" -replace -output "$binary" "$binary"
done
note "for macOS $MIN_MACOS and later, built with the macOS $SDK_VERSION SDK"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
fi
if [[ -n "${RELEASE_CANDIDATE:-}" ]]; then
    [[ "$RELEASE_CANDIDATE" =~ ^[1-9][0-9]*$ ]] || fail "RELEASE_CANDIDATE must be a number from 1"
    /usr/libexec/PlistBuddy -c "Add :AutoHushReleaseCandidate integer $RELEASE_CANDIDATE" "$APP_BUNDLE/Contents/Info.plist"
fi
note "version $(plist_value "$APP_BUNDLE/Contents/Info.plist" CFBundleShortVersionString)" \
     "($(plist_value "$APP_BUNDLE/Contents/Info.plist" CFBundleVersion))"

# The icon follows the light, dark, clear and tinted appearances on macOS 26
# and later (Assets.car); older systems get the flat AutoHush.icns. Info.plist
# names both. actool comes with Xcode.
step "Compiling the app icon"
if xcrun --find actool >/dev/null 2>&1; then
    ICON_INFO="$(mktemp)"
    trap 'rm -f "${ICON_INFO:?}"' EXIT # also when actool fails
    if ! ICON_LOG="$(xcrun actool "$APP_ICON" --compile "$APP_BUNDLE/Contents/Resources" \
            --platform macosx --minimum-deployment-target "$MIN_MACOS" \
            --app-icon "$APP_NAME" --output-partial-info-plist "$ICON_INFO" \
            --output-format human-readable-text 2>&1)"; then
        echo "$ICON_LOG" >&2
        fail "actool could not compile $APP_ICON"
    fi
else
    note "warning: actool not found (it comes with Xcode); the app keeps the generic icon"
fi

# Shortcuts and System Settings' Focus filters find the app's actions, its App
# Shortcuts and its Focus filter in Contents/Resources/Metadata.appintents,
# which Xcode writes and SwiftPM doesn't. appintentsmetadataprocessor reads
# them from AutoHushApp's sources and the constant values the compiler
# recorded for them (so their texts must be literals), and lists the texts
# only it sees, the actions' summaries, for the string catalog below. macOS
# indexes the actions once the app has run. It comes with Xcode.
INTENTS_STRINGSDATA=""
if PROCESSOR="$(xcrun --find appintentsmetadataprocessor 2>/dev/null)"; then
    step "Extracting App Intents metadata"
    # The compiler's map of AutoHushApp's sources to what it made of them,
    # the constant values among them: one file per source in a debug build,
    # one for the module in a release. Read from the map, a renamed or
    # deleted source's old file never counts. One kind of Mac's is enough,
    # as both give the same metadata: Apple silicon's, which a release always
    # has, or else Intel's (a debug build on an Intel Mac has only that).
    OBJECTS_DIR="$PROJECT_DIR/.build/out/Intermediates.noindex/AutoHush.build/$CONFIG_DIR/AutoHushApp-t.build/Objects-normal"
    INTENTS_ARCH=""
    for arch in arm64 x86_64; do
        if [[ -f "$OBJECTS_DIR/$arch/AutoHushApp-OutputFileMap.json" ]]; then
            INTENTS_ARCH="$arch"
            break
        fi
    done
    [[ -n "$INTENTS_ARCH" ]] \
        || fail "the compiler's output map for AutoHushApp is missing (${OBJECTS_DIR#"$PROJECT_DIR/"}/arm64 or x86_64/AutoHushApp-OutputFileMap.json)"
    OUTPUT_MAP="$OBJECTS_DIR/$INTENTS_ARCH/AutoHushApp-OutputFileMap.json"
    INTENTS_DIR="$PROJECT_DIR/.build/app-intents/$BUILD_CONFIG"
    rm -rf "${INTENTS_DIR:?}"
    mkdir -p "$INTENTS_DIR"
    jq -r 'keys[] | select(. != "")' "$OUTPUT_MAP" > "$INTENTS_DIR/AutoHushApp.SwiftFileList"
    jq -r '.[]["const-values"] // empty' "$OUTPUT_MAP" > "$INTENTS_DIR/AutoHushApp.SwiftConstValuesFileList"
    # The modules AutoHushApp uses have no App Intents of their own.
    : > "$INTENTS_DIR/AutoHushApp.DependencyMetadataFileList"
    : > "$INTENTS_DIR/AutoHushApp.DependencyStaticMetadataFileList"
    # The App Shortcuts' phrases have a catalog of their own
    # (AppShortcuts.xcstrings), so, as Xcode does then, the processor isn't
    # told they're untranslated (--no-app-shortcuts-localization).
    if ! INTENTS_LOG="$(xcrun appintentsmetadataprocessor \
            --toolchain-dir "${PROCESSOR%/usr/bin/appintentsmetadataprocessor}" \
            --module-name AutoHushApp \
            --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
            --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" \
            --platform-family macOS \
            --deployment-target "$MIN_MACOS" \
            --bundle-identifier "$BUNDLE_ID" \
            --output "$APP_BUNDLE/Contents/Resources" \
            --target-triple "$INTENTS_ARCH-apple-macos$MIN_MACOS" \
            --binary-file "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
            --stringsdata-file "$INTENTS_DIR/ExtractedAppShortcutsMetadata.stringsdata" \
            --source-file-list "$INTENTS_DIR/AutoHushApp.SwiftFileList" \
            --metadata-file-list "$INTENTS_DIR/AutoHushApp.DependencyMetadataFileList" \
            --static-metadata-file-list "$INTENTS_DIR/AutoHushApp.DependencyStaticMetadataFileList" \
            --swift-const-vals-list "$INTENTS_DIR/AutoHushApp.SwiftConstValuesFileList" \
            --force --compile-time-extraction --deployment-aware-processing 2>&1)"; then
        echo "$INTENTS_LOG" >&2
        fail "appintentsmetadataprocessor could not extract the App Intents metadata"
    fi
    ACTIONS_DATA="$APP_BUNDLE/Contents/Resources/Metadata.appintents/extract.actionsdata"
    if [[ ! -f "$ACTIONS_DATA" ]]; then
        echo "$INTENTS_LOG" >&2
        fail "appintentsmetadataprocessor wrote no ${ACTIONS_DATA#"$APP_BUNDLE/"}"
    fi
    INTENTS_STRINGSDATA="$INTENTS_DIR/ExtractedAppShortcutsMetadata.stringsdata"
    note "actions: $(jq -r '.actions | keys | join(" ")' "$ACTIONS_DATA");" \
         "App Shortcuts: $(jq '.autoShortcuts | length' "$ACTIONS_DATA")"
else
    note "warning: appintentsmetadataprocessor not found (it comes with Xcode); Shortcuts won't offer the app's actions"
fi

# Text people read lives in String Catalogs (Resources/Localization/). As Xcode
# does, each build adds the strings the code uses to Localizable.xcstrings and
# marks those it no longer uses as stale; then each translated language is
# compiled into its .lproj folder. macOS shows the first of the user's
# languages that AutoHush has, or else English (CFBundleDevelopmentRegion).
# xcstringstool comes with Xcode.
if xcrun --find xcstringstool >/dev/null 2>&1; then
    step "Updating the string catalog"
    # The compiler listed each source file's strings while building. A file
    # without its own list (one sharing its name with another module's file)
    # would make its strings look unused, so the catalog is then left alone.
    STRINGSDATA=()
    UNLISTED=()
    while IFS= read -r source; do
        data="$STRINGS_DIR/$(basename "$source" .swift).stringsdata"
        if [[ -f "$data" && "$(plutil -extract source raw -o - "$data" 2>/dev/null)" == *"/${source#"$PROJECT_DIR/"}" ]]; then
            STRINGSDATA+=(--stringsdata "$data")
        else
            UNLISTED+=("${source#"$PROJECT_DIR/"}")
        fi
    done < <(find "$PROJECT_DIR/Sources" -name '*.swift' | sort)
    # The actions' summaries are only in the App Intents step's list.
    if [[ -f "$INTENTS_STRINGSDATA" ]]; then
        STRINGSDATA+=(--stringsdata "$INTENTS_STRINGSDATA")
    else
        UNLISTED+=("the Shortcuts actions' summaries")
    fi
    if [[ ${#UNLISTED[@]} -eq 0 ]]; then
        xcrun xcstringstool sync "$STRING_CATALOG" "${STRINGSDATA[@]}"
        note "$(xcrun xcstringstool print "$STRING_CATALOG" | grep -c .) strings in ${STRING_CATALOG#"$PROJECT_DIR/"}"
    else
        note "warning: no string list for ${UNLISTED[*]}; ${STRING_CATALOG#"$PROJECT_DIR/"} was not updated"
    fi

    step "Compiling the translations"
    for catalog in "$LOCALIZATION_DIR"/*.xcstrings; do
        xcrun xcstringstool compile "$catalog" --output-directory "$APP_BUNDLE/Contents/Resources"
    done
    LANGUAGES="$(find "$APP_BUNDLE/Contents/Resources" -maxdepth 1 -name '*.lproj' -exec basename {} .lproj \; | sort | paste -sd ' ' -)"
    note "languages: ${LANGUAGES:-en}"
else
    note "warning: xcstringstool not found (it comes with Xcode); the app is built in English only"
fi

# A release ships without its local symbols, less than half the size (the
# App Intents step above has read them already). A published release's are
# kept for reading crash logs (KEEP_SYMBOLS=1, from release.sh): its dSYMs go
# to a folder of their own in dist/dSYMs/, named for its version, build and
# the app's UUID (which a crash log names); dist/ is git-ignored, so they
# stay on this Mac. Other release builds (checks, tests) keep none: 71 MB each.
if [[ "$BUILD_CONFIG" == release ]]; then
    DSYM_DIR=""
    if [[ "${KEEP_SYMBOLS:-0}" == 1 ]]; then
        step "Keeping the symbols, then stripping them"
        APP_UUID="$(xcrun dwarfdump --uuid "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | awk '/arm64/ {print $2; exit}')"
        DSYM_DIR="$DIST_DIR/dSYMs/$(plist_value "$APP_BUNDLE/Contents/Info.plist" CFBundleShortVersionString)-$(plist_value "$APP_BUNDLE/Contents/Info.plist" CFBundleVersion)-${APP_UUID:0:8}"
        mkdir -p "$DSYM_DIR"
    else
        step "Stripping the symbols"
    fi
    for binary in "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$HELPER"; do
        if [[ -n "${DSYM_DIR:-}" ]]; then
            xcrun dsymutil "$binary" -o "$DSYM_DIR/$(basename "$binary").dSYM" 2>/dev/null \
                || fail "dsymutil could not keep $(basename "$binary")'s symbols"
        fi
        xcrun strip -x "$binary"
    done
    if [[ -n "${DSYM_DIR:-}" ]]; then note "symbols kept in ${DSYM_DIR#"$PROJECT_DIR/"}"; fi
fi

IDENTITY="$(resolve_signing_identity)"
if [[ "$IDENTITY" == "-" ]]; then
    step "Signing ad hoc (hardened runtime)"
else
    step "Signing with \"$(identity_name "$IDENTITY")\" (hardened runtime)"
fi
# The helper first: the app's signature seals it as nested code.
sign_app "$IDENTITY" "$HELPER"
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
