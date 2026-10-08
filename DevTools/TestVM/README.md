# TestVM

Runs builds, tests and apps in a macOS virtual machine instead of the Mac
you work on, so live tests (sound, permissions, clean installs) don't
disturb it.

## What it does

`vm.sh [--gui] <command>` copies the project into the VM, then runs
`<command>` there, inside that copy. With `--gui`, the command runs in the
VM's desktop session, where apps open windows and Accessibility works.
`vm.sh sync` only copies. `vm.sh shot [name]` captures the VM's screen into
the transfer folder and prints where it is on the Mac
(`~/Applications/Tart/transfer`, or `AUTOHUSH_VM_TRANSFER`).

```bash
bash DevTools/TestVM/vm.sh 'swift test'
bash DevTools/TestVM/vm.sh 'KEEP_PERMISSIONS=1 bash Scripts/build-app.sh'
bash DevTools/TestVM/vm.sh --gui 'open -n AutoHush.app'
```

## How it works

- The VM is a [Tart](https://tart.run) VM named `autohush` (another name
  with `AUTOHUSH_VM`), made from Cirrus Labs' `macos-…-base` image, whose
  account is `admin`. Tart's guest agent runs the commands (`tart exec`),
  so no network access to the VM is needed.
- Start it with the working copy shared read-only and a folder for files
  coming back:
  `tart run autohush --dir=project:<working copy>:ro --dir=transfer:<folder>`.
  In the VM they're `/Volumes/My Shared Files/project` and `…/transfer`.
- Each run mirrors the share into `~/Documents/Projects/AutoHush` in the VM
  with `rsync --delete`, keeping `.build`, `AutoHush.app` and the harness's
  work folder, so builds use the VM's own disk and stay incremental.
- It then builds the test tools into `~/vmtools` when their source changed:
  [SoundNow](../SoundNow), [WindowList](../WindowList),
  [PageButtons](../PageButtons) and the [NoiseMaker](../NoiseMaker) app. It
  also installs [SwitchAudioSource](https://github.com/deweller/switchaudio-osx)
  (Homebrew's `switchaudio-osx`) to change the sound output:
  `SwitchAudioSource -t output -u AutoHushLoopback_UID` plays everything
  through [AutoHush Loopback](../LoopbackDriver).
- `--gui` wraps the command in `launchctl asuser 501`, the desktop user's
  session.
- The shared folder can show a file's previous content for a few seconds
  after it's edited on the Mac, so a run started right after an edit may
  mirror the old one: check the mirror (with `grep`) when it matters.

Signing in the VM needs the app's signing identity imported into the VM's
keychain. For permission tests, System Integrity Protection is off in the
VM, so permissions can be granted and taken away by writing to its TCC
database.
