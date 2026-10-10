#!/bin/bash
# Removes AutoHush Loopback (to the Trash; asks for an administrator's password)
# and restarts Core Audio.
set -euo pipefail
DEST="/Library/Audio/Plug-Ins/HAL/AutoHushLoopback.driver"
[ -d "$DEST" ] || { echo "AutoHush Loopback isn't installed."; exit 0; }
sudo mv "$DEST" "$HOME/.Trash/AutoHushLoopback-$(date +%Y%m%d-%H%M%S).driver"
sudo killall coreaudiod
echo "Removed: it's in the Trash."
