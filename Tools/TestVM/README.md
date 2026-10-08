# TestVM

Runs builds, tests and apps in a macOS virtual machine instead of the Mac
you work on, so live tests (sound, permissions, clean installs) don't
disturb it.

## What it does

`vm.sh [--gui] <command>` copies the project into the VM, then runs
`<command>` there, inside that copy. With `--gui`, the command runs in the
VM's desktop session, where apps open windows and Accessibility works.
`vm.sh sync` only copies.

```bash
bash Tools/TestVM/vm.sh 'swift test'
bash Tools/TestVM/vm.sh 'KEEP_PERMISSIONS=1 bash Scripts/build-app.sh'
bash Tools/TestVM/vm.sh --gui 'open -n AutoHush.app'
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
  [AudioOutput](../AudioOutput), [SoundNow](../SoundNow),
  [WindowList](../WindowList) and the [NoiseMaker](../NoiseMaker) app.
- `--gui` wraps the command in `launchctl asuser 501`, the desktop user's
  session.

Signing in the VM needs the app's signing identity imported into the VM's
keychain. For permission tests, System Integrity Protection is off in the
VM, so permissions can be granted and taken away by writing to its TCC
database.
