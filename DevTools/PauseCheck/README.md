# PauseCheck

Checks, in the test VM, that AutoHush pauses the music when another app
plays and resumes it afterwards, and how long each took.

```bash
bash DevTools/PauseCheck/pause-check.sh            # 8 s of sound
bash DevTools/PauseCheck/pause-check.sh 20 440     # 20 s of a 440 Hz tone
```

Before running it, AutoHush and its music player must be running and
playing in the VM (see [TestVM](../TestVM)), with the VM's output on
[AutoHush Loopback](../LoopbackDriver) so nothing is heard. Example output (shortened):

```
Noise Maker: started at 0.00 s, stopped at 8.03 s
   0.68 s  [monitor] +[com.autohush.test.noisemaker] -[]
   0.68 s  [fade] out from 50 (user volume 50)
   2.07 s  [arbiter] VLC paused
  10.18 s  [monitor] +[] -[com.autohush.test.noisemaker]
  12.34 s  [arbiter] VLC resumed
Verdict: paused 2.07 s after the sound started
         resumed 4.31 s after it stopped
```

"Paused" comes after the fade-out; the resume waits for AutoHush's "Resume
music after" time, then fades in.

## How it works

In the VM (through `tart exec`), it records AutoHush's log with
`log stream --level debug` (its monitor, arbiter and fade lines are debug
level, which `log show` doesn't keep), opens [NoiseMaker](../NoiseMaker) in
the desktop session for the given time, waits for the resume, then lines the
log up with Noise Maker's own start and stop times (`/tmp/noisemaker.log`)
in a short Python script. The player's own sound isn't used to tell a pause:
some players, like VLC, keep their audio output open while paused.
