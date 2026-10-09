# MediaKey

Presses the keyboard's Play/Pause key, as a user would. macOS sends it to
the app it counts as playing now ("Now Playing"), not to an app of our
choice. Used to test whether that key pauses a Safari web app, and whether
the page's own Play/Pause button changes its words when it does.

```bash
swiftc -O -o mediakey DevTools/MediaKey/mediakey.swift
./mediakey
```

## How it works

It builds the key's system event (`NSEvent.otherEvent`, type
`systemDefined`, subtype 8, `NX_KEYTYPE_PLAY`), down then up, and posts it
to the HID event tap (`CGEvent.post`). Posting events needs the
Accessibility permission.

## Trying it on a web app, with a person

```bash
sh DevTools/MediaKey/ask-on-mac.sh "YT Music"
```

From the project's folder on the Mac: a dialog waits until the person has
a song playing in the test VM (not an ad) and clicks Run Test. Then, in the
VM, `try-webapp.sh` presses the key twice, three seconds apart, and the
dialog shows the app's sound before and after each press (SoundNow) and the
page buttons whose words changed (PageButtons), the way AutoHush learns a
web app's Play/Pause button. Each run is logged in the transfer folder's
`mediakey/`. The VM needs `mediakey`, `soundnow` and `pagebuttons` built in
`~/vmtools`.
