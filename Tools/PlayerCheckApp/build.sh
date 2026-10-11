#!/bin/sh
# Builds "Player Check.app" into a folder (default: the current one): the
# window, with Tools/PlayerCheck's playercheck inside its Resources.
#   sh Tools/PlayerCheckApp/build.sh [folder]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
app="${1:-.}/Player Check.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$here/Info.plist" "$app/Contents/Info.plist"
swiftc -O -parse-as-library -o "$app/Contents/MacOS/PlayerCheckApp" "$here/PlayerCheckApp.swift"
swiftc -O -o "$app/Contents/Resources/playercheck" "$here/../PlayerCheck/playercheck.swift"
codesign --force -s - "$app/Contents/Resources/playercheck"
codesign --force -s - "$app"
echo "$app"
