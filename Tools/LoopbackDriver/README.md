# LoopbackDriver

AutoHush Loopback: a virtual audio device for tests, never shipped with
AutoHush. Whatever plays to its output comes back on its input, so a test
can hear exactly what would have reached the speakers, silently, and
[ListenToFades](../ListenToFades) can record and measure it.

```bash
bash Tools/LoopbackDriver/build.sh       # into .build/loopback/AutoHushLoopback.driver
bash Tools/LoopbackDriver/install.sh     # asks for an administrator's password
SwitchAudioSource -t output -u AutoHushLoopback_UID   # play everything through it
bash Tools/LoopbackDriver/uninstall.sh   # when testing is over (to the Trash)
```

`SwitchAudioSource` is Homebrew's `switchaudio-osx`; switch the output back
afterwards. Alert sounds stay on the Mac's own output: the device says it
can't be the system device. While it's the output, any app allowed to use
the microphone can record what plays through it, so uninstall it when it's
no longer needed. Installing or removing it restarts Core Audio, which
interrupts every app's sound for a moment.

## How it works

A Core Audio server plug-in (`AudioServerPlugIn.h`), written in C: one
device, "AutoHush Loopback" (UID `AutoHushLoopback_UID`), 48 kHz stereo
32-bit float, with one output and one input stream sharing a ring buffer
of about a third of a second. The output is written into the ring at its
sample time; the input reads the same sample times back, then clears them,
so nothing old loops. `build.sh` compiles it for Apple silicon and Intel
and signs it ad hoc; `install.sh` copies it into
`/Library/Audio/Plug-Ins/HAL` (an older copy goes to the Trash) and
restarts `coreaudiod`.
