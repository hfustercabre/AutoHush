#!/bin/sh
# One try of the Play/Pause key on a web app that plays a song now: the key
# is pressed twice, three seconds apart, and what changed (its sound, the
# page's button words) is printed and logged. Run it in the app's Mac (the
# VM), once a person has a song playing (not an ad); ask-on-mac.sh asks them.
# Usage: try-webapp.sh "<app name>" [log folder]
APP="${1:?usage: try-webapp.sh <app name> [log folder]}"
LOG="${2:-/tmp/mediakey}"
T="${TOOLS:-$HOME/vmtools}"
mkdir -p "$LOG"

# The page's buttons, by name only, in the page's order.
labels() {
    "$T/pagebuttons" "$APP" list 2>&1 | sed -n '2,$p' \
        | sed -E 's/ \| ([0-9-]+ pt from the bottom|no frame)( \|.*)?$//; s/^ *//' | tr -d '"\\'
}
# The buttons whose name changed between two lists.
changed() {
    if [ "$(wc -l < "$1")" -eq "$(wc -l < "$2")" ]; then
        paste -d '\t' "$1" "$2" | awk -F '\t' '$1 != $2 { print $1 " -> " $2 }' | head -5
    else
        echo "($(wc -l < "$1" | tr -d ' ') buttons before, $(wc -l < "$2" | tr -d ' ') after)"
    fi
}
sound() { "$T/soundnow" 2>&1 | tr -d '"\\' | tr '\n' ' '; }

n=$(( $(ls "$LOG" | grep -c '^run-') + 1 ))
s0=$(sound); labels > "$LOG/b0"
k1=$("$T/mediakey" | head -1); sleep 3
s1=$(sound); labels > "$LOG/b1"
"$T/mediakey" > /dev/null; sleep 3
s2=$(sound); labels > "$LOG/b2"
c1=$(changed "$LOG/b0" "$LOG/b1"); c2=$(changed "$LOG/b1" "$LOG/b2")
{
    echo "Run $n at $(date +%T) ($k1, $(wc -l < "$LOG/b0" | tr -d ' ') buttons)"
    echo ""
    echo "Before: $s0"
    echo ""
    echo "After the 1st press: $s1"
    echo "Changed: ${c1:-nothing}"
    echo ""
    echo "After the 2nd press: $s2"
    echo "Changed: ${c2:-nothing}"
} | tee "$LOG/run-$n.txt"
