# NoiseMaker

A test app that stands in for "another app playing sound": it plays a tone
or a file for a while, then quits. AutoHush sees it like any app with its
own bundle ID (`com.autohush.test.noisemaker`), so it pauses the music for
it and resumes afterwards.

## Use

```bash
open -n NoiseMaker.app --args --tone 523.25 --seconds 8
open -n NoiseMaker.app --args --file music.aiff --seconds inf --volume 0.3
```

Defaults: a 440 Hz tone for 8 s at volume 0.5. A file loops for the time
given; `inf` plays until it's quit (SIGTERM stops it cleanly). Each start
and stop is appended to `/tmp/noisemaker.log` as `<epoch seconds> start|stop
…`, to line a test's timeline up with AutoHush's log.

## How it works

`main.swift` is an AppKit app with no Dock icon or window (`LSUIElement`),
so it never takes the focus. The tone comes from an `AVAudioSourceNode`
(a sine, in an `AVAudioEngine`); a file plays through `AVAudioPlayer`. A
timer quits it after `--seconds`.

Build it into an app bundle (the [TestVM](../TestVM) script does this in
the VM, into `~/vmtools`):

```bash
mkdir -p NoiseMaker.app/Contents/MacOS
cp DevTools/NoiseMaker/Info.plist NoiseMaker.app/Contents/
swiftc -swift-version 5 -O -o NoiseMaker.app/Contents/MacOS/NoiseMaker DevTools/NoiseMaker/main.swift
codesign --force -s - NoiseMaker.app
```
