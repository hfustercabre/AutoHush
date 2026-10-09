#!/bin/sh
# Runs try-webapp.sh in the test VM each time the person clicks Run Test in a
# dialog on this Mac, and shows them the result. Finish ends it.
# Usage: ask-on-mac.sh "<app name>"   (from the project's folder)
APP="${1:?usage: ask-on-mac.sh <app name>}"
LOG="/Volumes/My Shared Files/transfer/mediakey"
dialog() {  # message, buttons
    osascript -e "display dialog \"$(printf '%s' "$1" | tr -d '"\\')\" with title \"Play/Pause key test\" buttons {$2} giving up after 3600" \
        -e 'button returned of result' 2>/dev/null
}
bash DevTools/TestVM/vm.sh --gui "open -a '$APP'" > /dev/null 2>&1
while [ "$(dialog "Play a song in $APP in the VM (not an ad). When it plays, click Run Test." '"Finish", "Run Test"')" = "Run Test" ]; do
    result=$(bash DevTools/TestVM/vm.sh --gui "sh DevTools/MediaKey/try-webapp.sh '$APP' '$LOG'" 2>&1 | grep -v '^vm.sh:')
    echo "$result"; echo "-----"
    [ "$(dialog "$result" '"Finish", "Again"')" = "Again" ] || break
done
