# Tools

Tools for measuring AutoHush's fades and for checking which apps it could
control. **None of them is part of the app or its disk image:** no app
target depends on them, `Scripts/build-app.sh` builds only AutoHush and its
helper, playercheck (both from `Sources/`), and what the build itself needs
lives in `Scripts/`.

| Tool | What it does |
|---|---|
| [MeasureVolumeCurve](MeasureVolumeCurve) | Measures how a media player's volume number maps to loudness, for its fade curve (`swift run measure-volume-curve`). |
| [ListenToFades](ListenToFades) | Records the Mac's sound through AutoHush Loopback and measures each fade (`swift run listen-to-fades`). |
| [LoopbackDriver](LoopbackDriver) | AutoHush Loopback, a virtual audio device whose output comes back on its input, for silent, measurable tests. |
| [PlayerCheckApp](PlayerCheckApp) | Player Check, [PlayerCheck](../Sources/PlayerCheck) in a window (PlayerCheck is part of AutoHush, which runs it for Add an App…): lists the apps that can be in Now Playing, checks the one you pick, and plays and pauses those with a known way (`sh Tools/PlayerCheckApp/build.sh`: the package's `PlayerCheckApp` product, in an app). |

Each folder has a README saying what the tool does and how it works.
