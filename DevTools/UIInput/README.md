# UIInput

Clicks, drags and scrolls in the desktop session, as a person's hand would:
for windows that scripting can't reach, such as a VM's permission prompts,
SwiftUI buttons inside a window, Gatekeeper's dialogs or Mission Control.

```bash
/usr/bin/python3 DevTools/UIInput/uiinput.py click 512 427
/usr/bin/python3 DevTools/UIInput/uiinput.py drag 370 262 669 262   # e.g. AutoHush onto Applications in the DMG
/usr/bin/python3 DevTools/UIInput/uiinput.py scroll 506 422 -20    # negative: down
```

Coordinates are points from the top left of the main screen: on a Retina
capture, half the pixels. Run it in the session that owns the screen (in
the test VM: `vm.sh --gui`, or `sudo launchctl asuser 501 sudo -u admin`);
the process posting the events needs Accessibility.

## How it works

It posts Quartz mouse events (`CGEventCreateMouseEvent`,
`CGEventCreateScrollWheelEvent`) to the HID event tap, through Python's
`ctypes`, so nothing has to be built. A drag sends the moves in between,
which Finder needs to take a drop. Keyboard events posted this way are
ignored by VoiceOver; use System Events' `key code` for those.
