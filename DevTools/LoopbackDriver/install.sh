#!/bin/bash
# Installs AutoHush Loopback into /Library/Audio/Plug-Ins/HAL (asks for an
# administrator's password) and restarts Core Audio, which interrupts every
# app's sound for a moment. A copy already there goes to the Trash.
# Remove it with uninstall.sh once the tests are done.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../../.build/loopback/AutoHushLoopback.driver"
DEST="/Library/Audio/Plug-Ins/HAL/AutoHushLoopback.driver"
[ -d "$SRC" ] || { echo "Build it first: bash DevTools/LoopbackDriver/build.sh"; exit 1; }
if [ -d "$DEST" ]; then sudo mv "$DEST" "$HOME/.Trash/AutoHushLoopback-$(date +%Y%m%d-%H%M%S).driver"; fi
sudo cp -R "$SRC" "$DEST"
sudo chown -R root:wheel "$DEST"
sudo killall coreaudiod
echo "Installed: \"AutoHush Loopback\" shows in Sound's output list in a few seconds."
echo "While it's the output, any app allowed to use the microphone can record what plays through it."
echo "Switch the output back when you're done, and run uninstall.sh once you no longer test."
