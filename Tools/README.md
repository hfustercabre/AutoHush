# Tools

Tools for measuring AutoHush's fades and for checking which apps it could
control. **None of them is part of the app or its disk image:** no app target depends on them, `Scripts/build-app.sh`
builds only the AutoHush product, and what the build itself needs lives in
`Scripts/`.

| Tool | What it does |
|---|---|
| [MeasureVolumeCurve](MeasureVolumeCurve) | Measures how a media player's volume number maps to loudness, for its fade curve (`swift run measure-volume-curve`). |
| [ListenToFades](ListenToFades) | Records the Mac's sound through AutoHush Loopback and measures each fade (`swift run listen-to-fades`). |
| [LoopbackDriver](LoopbackDriver) | AutoHush Loopback, a virtual audio device whose output comes back on its input, for silent, measurable tests. |
| [PlayerCheck](PlayerCheck) | Says whether AutoHush could control an app, and how: reads its scripting dictionary, playback menu, sound, Now Playing and page buttons, then tests each way to control it (pausing and playing it) and lists what worked; it can also play and pause the app. |
| [PlayerCheckApp](PlayerCheckApp) | Player Check, PlayerCheck in a window: lists the apps that can be in Now Playing, checks the one you pick, and plays and pauses those with a known way. |

Each folder has a README saying what the tool does and how it works.
