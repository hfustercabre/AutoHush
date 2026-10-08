#!/bin/bash
# pause-check.sh [seconds] [tone Hz]: in the test VM, plays Noise Maker for
# [seconds] (default 8) while AutoHush and its music player run, then prints
# what AutoHush did and when, timed from the sound's start. See README.md.
set -euo pipefail
VM="${AUTOHUSH_VM:-autohush}"
SECONDS_ON="${1:-8}"
TONE="${2:-523.25}"
WAIT=$(( ${SECONDS_ON%.*} + 14 ))

tart exec "$VM" sh -c '
pgrep -x AutoHush >/dev/null || { echo "AutoHush is not running in the VM"; exit 1; }
[ -d ~/vmtools/NoiseMaker.app ] || { echo "Noise Maker is not built: run Tools/TestVM/vm.sh sync"; exit 1; }
rm -f /tmp/noisemaker.log /tmp/pause-check.log
log stream --level debug --style compact --predicate "subsystem == \"com.autohush.AutoHush\"" > /tmp/pause-check.log 2>&1 &
stream=$!
sleep 2
sudo launchctl asuser 501 sudo -u admin open -n ~/vmtools/NoiseMaker.app --args --tone '"$TONE"' --seconds '"$SECONDS_ON"'
sleep '"$WAIT"'
kill $stream; wait $stream 2>/dev/null
python3 - <<"PY"
import datetime, re
noise = [l.split() for l in open("/tmp/noisemaker.log")]
start = float(next(l[0] for l in noise if l[1] == "start"))
stop = next((float(l[0]) for l in noise if l[1] == "stop"), None)
def t(line):
    m = re.match(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)", line)
    return datetime.datetime.strptime(m.group(1)[:26], "%Y-%m-%d %H:%M:%S.%f").timestamp() if m else None
print(f"Noise Maker: started at 0.00 s, stopped at {stop - start:.2f} s" if stop else "Noise Maker: no stop logged")
paused = resumed = None
for line in open("/tmp/pause-check.log"):
    when = t(line)
    if when is None or not re.search(r"\[(monitor|arbiter|fade)\]", line):
        continue
    text = re.sub(r"^\[com\.autohush\.AutoHush:\w+\] ", "", line.split("] ", 1)[-1].strip())
    print(f"{when - start:7.2f} s  {text}")
    if paused is None and re.search(r"\] \S.* paused", line): paused = when - start
    if paused is not None and re.search(r" resumed", line): resumed = when - start
print(f"Verdict: paused {paused:.2f} s after the sound started" if paused is not None else "Verdict: NOT paused")
if resumed is not None and stop: print(f"         resumed {resumed - (stop - start):.2f} s after it stopped")
elif paused is not None: print("         NOT resumed")
PY'
