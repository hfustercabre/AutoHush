# DevTools

Tools for developing and testing AutoHush. **None of them is part of the
app or its disk image:** no app target depends on them, `Scripts/build-app.sh`
builds only the AutoHush product, and what the build itself needs lives in
`Scripts/`.

| Tool | What it does |
|---|---|
| [MeasureVolumeCurve](MeasureVolumeCurve) | Measures how a music player's volume number maps to loudness, for its fade curve (`swift run measure-volume-curve`). |
| [ListenToFades](ListenToFades) | Records the Mac's sound through AutoHush Loopback and measures each fade (`swift run listen-to-fades`). |
| [LoopbackDriver](LoopbackDriver) | AutoHush Loopback, a virtual audio device whose output comes back on its input, for silent, measurable tests. |
| [TestVM](TestVM) | Runs builds, tests and apps in a macOS virtual machine, so live tests don't disturb the Mac you work on. |
| [NoiseMaker](NoiseMaker) | A test app that plays a tone or a file, standing in for "another app playing sound". |
| [PauseCheck](PauseCheck) | In the test VM, times AutoHush's pause and resume around a Noise Maker sound. |
| [PageButtons](PageButtons) | Lists or presses a web page's buttons by name, the way AutoHush reads them, to drive a web app in tests. |
| [UIInput](UIInput) | Clicks, drags and scrolls in the desktop session, for windows scripting can't reach (a VM's prompts, SwiftUI buttons). |
| [SoundNow](SoundNow) | Lists the apps playing sound right now, the way AutoHush counts them. |
| [WindowList](WindowList) | Lists an app's windows with their size, place and title. |
| [MemWatch](MemWatch) | Samples a process's memory over hours, to show whether it leaks. |

Each folder has a README saying what the tool does and how it works.
