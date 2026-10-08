#!/bin/bash
# vm.sh [--gui] <command…>: mirrors this project into the test VM, then runs
# <command> there, in the mirror. --gui runs it in the VM's desktop session
# (apps, windows, Accessibility). `vm.sh sync` only mirrors. See README.md.
set -euo pipefail
VM="${AUTOHUSH_VM:-autohush}"
MIRROR=/Users/admin/Documents/Projects/AutoHush
gui=0
if [[ "${1:-}" == "--gui" ]]; then gui=1; shift; fi

# The project, from the VM's read-only share of the working copy; builds stay
# on the VM's own disk.
tart exec "$VM" rsync -a --delete \
    --exclude .build --exclude AutoHush.app --exclude Harness/.work \
    "/Volumes/My Shared Files/project/" "$MIRROR/"

# The test tools, built in the VM outside the mirror, into ~/vmtools: a
# command-line tool per Swift file, and the Noise Maker app.
tart exec "$VM" sh -c 'mkdir -p ~/vmtools; T='"$MIRROR"'/Tools
for tool in AudioOutput/audioout SoundNow/soundnow WindowList/cgwins; do
    src="$T/$tool.swift"; bin=~/vmtools/$(basename "$tool")
    [ -f "$src" ] && { [ "$bin" -nt "$src" ] || swiftc -O -o "$bin" "$src" 2>/dev/null; }
done
app=~/vmtools/NoiseMaker.app
if [ -f "$T/NoiseMaker/main.swift" ] && ! [ "$app/Contents/MacOS/NoiseMaker" -nt "$T/NoiseMaker/main.swift" ]; then
    mkdir -p "$app/Contents/MacOS" && cp "$T/NoiseMaker/Info.plist" "$app/Contents/Info.plist" &&
    swiftc -swift-version 5 -suppress-warnings -O -o "$app/Contents/MacOS/NoiseMaker" "$T/NoiseMaker/main.swift" &&
    codesign --force -s - "$app" >/dev/null 2>&1 || echo "Noise Maker did not build" >&2
fi'

[[ "${1:-}" == "sync" || $# -eq 0 ]] && exit 0
if [[ $gui == 1 ]]; then
    exec tart exec "$VM" sudo launchctl asuser 501 sudo -u admin sh -c "cd $MIRROR && $*"
else
    exec tart exec "$VM" sh -c "cd $MIRROR && $*"
fi
