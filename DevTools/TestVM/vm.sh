#!/bin/bash
# vm.sh [--gui] <command…>: mirrors this project into the test VM, then runs
# <command> there, in the mirror. --gui runs it in the VM's desktop session
# (apps, windows, Accessibility). `vm.sh sync` only mirrors. `vm.sh shot
# [name]` captures the VM's screen into the transfer folder and prints the
# file's path on this Mac. See README.md.
set -euo pipefail
VM="${AUTOHUSH_VM:-autohush}"
MIRROR=/Users/admin/Documents/Projects/AutoHush
TRANSFER="${AUTOHUSH_VM_TRANSFER:-$HOME/Applications/Tart/transfer}"
gui=0
if [[ "${1:-}" == "shot" ]]; then
    name="${2:-vm-screen}"
    # It goes into a command in the VM: a plain file name only.
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "vm.sh shot: use letters, digits, '.', '_' or '-' in the name" >&2; exit 2; }
    # Captured on the VM's disk first: written straight into the shared
    # folder, screencapture can hang setting the file's metadata.
    tart exec "$VM" sh -c "sudo launchctl asuser 501 sudo -u admin perl -e 'alarm 30; exec @ARGV' screencapture -x /tmp/$name.png && cp /tmp/$name.png '/Volumes/My Shared Files/transfer/$name.png'"
    echo "$TRANSFER/$name.png"
    exit 0
fi
if [[ "${1:-}" == "--gui" ]]; then gui=1; shift; fi

# The project, from the VM's read-only share of the working copy; builds stay
# on the VM's own disk.
tart exec "$VM" rsync -a --delete \
    --exclude .build --exclude AutoHush.app --exclude Harness/.work \
    "/Volumes/My Shared Files/project/" "$MIRROR/"

# The test tools, built in the VM outside the mirror, into ~/vmtools: a
# command-line tool per Swift file, and the Noise Maker app. SwitchAudioSource
# (Homebrew's switchaudio-osx) changes the sound output.
tart exec "$VM" sh -c 'mkdir -p ~/vmtools; T='"$MIRROR"'/DevTools
[ -x /opt/homebrew/bin/SwitchAudioSource ] || HOMEBREW_NO_AUTO_UPDATE=1 /opt/homebrew/bin/brew install -q switchaudio-osx >/dev/null
for tool in SoundNow/soundnow WindowList/cgwins PageButtons/pagebuttons; do
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
