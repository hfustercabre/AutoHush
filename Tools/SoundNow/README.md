# SoundNow

Lists the apps playing sound right now, the way AutoHush counts them.
Read only.

```bash
swiftc -O -o soundnow Tools/SoundNow/soundnow.swift
./soundnow          # e.g. "6044 VLC", or "silent"
```

Polled in a loop, it gives a test's timeline: when the music stops for
another app and when it comes back.

## How it works

It asks Core Audio for its process objects
(`kAudioHardwarePropertyProcessObjectList`) and keeps those whose output is
running (`kAudioProcessPropertyIsRunningOutput`). Each is reported as the
process macOS holds responsible for it
(`responsibility_get_pid_responsible_for_pid`, looked up at runtime), so a
web app's WebKit process counts as the web app and a command-line player as
the app that started it, as in AutoHush. Names come from
`NSRunningApplication`; `?` marks a process that isn't an app.
