# MeasureVolumeCurve

Measures how a music player turns its volume number (0–100) into loudness,
so its `VolumeCurve` can be set and AutoHush's fades sound even.

```bash
swift run measure-volume-curve com.spotify.client          # the default volumes
swift run measure-volume-curve com.apple.Music 75 50 25    # chosen volumes
```

The player must be running; the tool makes it play at changing volumes for
about 50 seconds, then gives it its volume and play state back. Any supported
player works (without a bundle ID, the first one offered). macOS asks once
for permission to record system audio and to control the player. Nothing is
recorded or stored: the output is only metered.

## How it works

It reads the player's output through AutoHush's own process-tap meter. For
each volume it alternates with 100 several times (4 pairs, 0.2 s to settle
and 0.3 s to measure each) and reports the median level difference in dB,
which cancels out the music's own ups and downs. Measured this way:
Spotify follows a cube law, Apple Music is linear.
