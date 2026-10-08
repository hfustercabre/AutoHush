# MemWatch

Samples a process's memory over hours, to show whether it leaks. Read
only.

```bash
bash Tools/MemWatch/memwatch.sh <pid> memwatch.txt 180 60   # 3 hours, every minute
```

Each line is the time, the physical footprint (what Activity Monitor calls
Memory), the resident size in MB and the CPU time used so far. It stops
early, and says so, if the process ends. A footprint that settles after
launch and stays flat means no leak; one that keeps rising means a leak.

## How it works

A shell loop: `footprint -p <pid>` for the footprint, `ps -o rss=,time=`
for the resident size and CPU time, then `sleep`. Run it in the
background, and don't restart the app meanwhile.
