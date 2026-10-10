#!/bin/sh
# Runs in the old macOS VM (from "Run in VM.command"): captures the harness's
# real menu (its players unfolded too), every Settings page and the other
# windows (welcome, Add a Web App, learning), checks that AutoHush shows in
# the Dock only while a window is open, copying each capture and the app's
# output (run.log) to the shared transfer folder as it goes, then leaves
# Settings open to try by hand.
HERE=/Users/admin/OldMacVM
APP="$HERE/Harness.app/Contents/MacOS/AutoHush"
OUT="$HERE/captures"
SHARED="/Volumes/My Shared Files/transfer/vm15/captures"
LOG="$SHARED/run.log"
mkdir -p "$OUT" "$SHARED"
sw_vers > "$SHARED/sw_vers.txt"
export SELFCAPTURE=1
run() { # <name> <arguments…>: one run, logged, its captures copied over
    echo "== $1" >> "$LOG"; shift
    "$APP" "$@" "$OUT" >> "$LOG" 2>&1
    echo "exit $?" >> "$LOG"
    cp "$OUT"/*.png "$SHARED/" 2>> "$LOG"
}
run menu --real-menu
USTYLE=NOW FAKEWEB=1 PICKAT=90,228 run windows --window-style
run dock --dock-check
for page in general apps detection fades diagnostics updates about; do
    TAB=$page run "$page" --settings-mock
done
ANTIDOT=1 TAB=detection run detection-antidot --settings-mock
echo "== live" >> "$LOG"
KEEP=1 TAB=general "$APP" --settings-mock "$OUT" >> "$LOG" 2>&1
