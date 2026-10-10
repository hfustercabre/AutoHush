#!/bin/sh
# Double-click it inside the old macOS VM (Finder → My Shared Files →
# transfer → vm15): copies the app and harness-run.sh from the shared folder
# to the VM's own disk, then runs it there. See README.md.
SRC="/Volumes/My Shared Files/transfer/vm15"
HERE="$HOME/OldMacVM"
mkdir -p "$HERE"
ditto "$SRC/Harness.app" "$HERE/Harness.app" || exit 1
cp "$SRC/harness-run.sh" "$HERE/run.sh" || exit 1
sh "$HERE/run.sh"
