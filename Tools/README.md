# Tools

Tools for measuring AutoHush's fades. **None of them is part of the app or
its disk image:** no app target depends on them, `Scripts/build-app.sh`
builds only the AutoHush product, and what the build itself needs lives in
`Scripts/`.

| Tool | What it does |
|---|---|
| [MeasureVolumeCurve](MeasureVolumeCurve) | Measures how a media player's volume number maps to loudness, for its fade curve (`swift run measure-volume-curve`). |
| [ListenToFades](ListenToFades) | Records the Mac's sound through AutoHush Loopback and measures each fade (`swift run listen-to-fades`). |
| [LoopbackDriver](LoopbackDriver) | AutoHush Loopback, a virtual audio device whose output comes back on its input, for silent, measurable tests. |

Each folder has a README saying what the tool does and how it works.
