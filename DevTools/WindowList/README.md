# WindowList

Lists one app's windows, front to back, with their number, size, position,
whether they're on screen, and title. Read only.

```bash
swiftc -O -o cgwins DevTools/WindowList/cgwins.swift
./cgwins AutoHush        # by app name, or by process ID
```

Uses: checking where a window opened (centered, on screen, in front of
other apps' windows), and getting a window's number to capture just that
window: `screencapture -o -x -l <number> window.png`.

## How it works

`CGWindowListCopyWindowInfo` with `.optionAll` returns every window in the
window server, front to back, including those on other desktops or not on
screen. It keeps the ones whose owner matches, by process ID or name, and
prints `kCGWindowNumber`, `kCGWindowLayer`, `kCGWindowIsOnscreen`,
`kCGWindowBounds` and `kCGWindowName`. Titles need the Screen Recording
permission; without it they're empty.
