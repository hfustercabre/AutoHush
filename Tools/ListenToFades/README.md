# ListenToFades

Records what the Mac plays while AutoHush fades the music, then measures
the music's loudness through each fade: whether it falls and rises evenly,
and whether there are dropouts or jumps.

```bash
SwitchAudioSource -t output -u AutoHushLoopback_UID     # play through the loopback
log stream --level debug --style compact \
    --predicate 'subsystem == "com.autohush.AutoHush"' > fades.log &
swift run listen-to-fades record 30 fades.wav          # meanwhile, make AutoHush fade
swift run listen-to-fades analyze fades.wav --log fades.log [--fade-out 1] [--fade-in 2]
```

It needs [AutoHush Loopback](../LoopbackDriver) as the output (you hear
nothing meanwhile; switch it back afterwards) and the Microphone permission
for the app that runs it (macOS asks once). Only that device is read
(`--device <UID>` picks another). The other app's sound is expected to be a
523 Hz tone, which the analysis removes.

## How it works

`record` reads the loopback device's input with Core Audio and writes a WAV
file. `analyze` takes the fades' times from AutoHush's log: AutoHush logs
fades at debug level, which macOS keeps only for a live `log stream`, so
capture one during the test and pass it with `--log` (otherwise it asks
`log show`, which may find none). For every fade it prints the music's
level every 50 ms next to an ideal straight-line fade in decibels, the
level every 5 ms around the moments AutoHush pauses and plays, and any
dropouts or jumps.
