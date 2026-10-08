#!/bin/bash
# Builds AutoHush Loopback, a test-only virtual audio device (see AutoHushLoopback.c),
# into .build/loopback/AutoHushLoopback.driver. Install it with install.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../../.build/loopback/AutoHushLoopback.driver"
rm -rf "${OUT:?}"
mkdir -p "$OUT/Contents/MacOS"
clang -bundle -O2 -Wall -Wextra -arch arm64 -arch x86_64 -mmacosx-version-min=14.2 \
    -framework CoreAudio -framework CoreFoundation \
    -o "$OUT/Contents/MacOS/AutoHushLoopback" "$HERE/AutoHushLoopback.c"
cp "$HERE/Info.plist" "$OUT/Contents/Info.plist"
codesign --force --sign - "$OUT"
echo "Built: $OUT"
