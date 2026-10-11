#!/bin/sh
# Builds "Player Check.app" into a folder (default: the current one): the
# window, with Tools/PlayerCheck's playercheck inside its Resources.
#   sh Tools/PlayerCheckApp/build.sh [folder]
#   SIGNING_IDENTITY="<certificate>" sh Tools/PlayerCheckApp/build.sh [folder]
# Signed ad hoc by default ("-"): macOS then knows each build by its content,
# so a rebuilt one asks for Accessibility again. Signed with a code signing
# certificate from the keychain, rebuilds keep the permissions.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
app="${1:-.}/Player Check.app"
identity="${SIGNING_IDENTITY:--}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$here/Info.plist" "$app/Contents/Info.plist"
swiftc -O -parse-as-library -o "$app/Contents/MacOS/PlayerCheckApp" "$here/PlayerCheckApp.swift"
swiftc -O -o "$app/Contents/Resources/playercheck" "$here/../PlayerCheck/playercheck.swift"
codesign --force -s "$identity" --timestamp=none "$app/Contents/Resources/playercheck"
codesign --force -s "$identity" --timestamp=none "$app"
echo "$app"
