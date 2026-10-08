# AudioOutput

Reads or changes the Mac's sound output from the command line, for tests
that play through [AutoHush Loopback](../LoopbackDriver) instead of the
speakers.

```bash
swiftc -O -o audioout Tools/AudioOutput/audioout.swift
./audioout list                        # every output: UID and name
./audioout get                         # the current one
./audioout set AutoHushLoopback_UID    # use the loopback
./audioout set BuiltInSpeakerDevice    # back to the speakers
```

Note the output before a test and set it back afterwards.

## How it works

Core Audio's system object: `kAudioHardwarePropertyDevices` lists the
devices (those with output streams are outputs),
`kAudioHardwarePropertyDefaultOutputDevice` is the output, and `set`
changes it together with the alerts' output
(`kAudioHardwarePropertyDefaultSystemOutputDevice`). Devices are named by
their UID, which stays the same across restarts.
