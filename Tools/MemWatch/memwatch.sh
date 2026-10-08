#!/bin/bash
# memwatch.sh <pid> <output file> [minutes=180] [interval seconds=60]
# Samples a process's memory over time (read only): its physical footprint
# (what Activity Monitor calls Memory), resident size and CPU time.
# Stops early if the process ends.
pid=$1; out=$2; minutes=${3:-180}; every=${4:-60}
echo "# memwatch pid $pid, $(ps -o comm= -p "$pid"), every ${every}s for ${minutes} min, from $(date '+%Y-%m-%d %H:%M:%S')" > "$out"
echo "# time      footprint_MB  rss_MB  cpu_time" >> "$out"
end=$(( $(date +%s) + minutes * 60 ))
while [ "$(date +%s)" -lt "$end" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then echo "# $(date '+%H:%M:%S') process ended" >> "$out"; exit 1; fi
    fp=$(footprint -p "$pid" 2>/dev/null | sed -n 's/.*Footprint: \([0-9.]*\) \([KMG]B\).*/\1 \2/p' | head -1)
    read -r rss cpu <<<"$(ps -o rss=,time= -p "$pid")"
    printf '%s  %-12s  %-6s  %s\n' "$(date '+%H:%M:%S')" "$fp" "$((rss / 1024))" "$cpu" >> "$out"
    sleep "$every"
done
echo "# $(date '+%H:%M:%S') done" >> "$out"
