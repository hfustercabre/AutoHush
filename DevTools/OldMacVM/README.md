# OldMacVM

Runs an app in a Tart VM of an older macOS, such as macOS 15.0 (the first
version AutoHush supports), to see how it looks there. It's made for
AutoHush's mockup harness, a local tool kept out of this repository
(`Harness/`): `harness-run.sh` runs its modes (`--real-menu`,
`--window-style`, `--dock-check`, `--settings-mock`). For another app,
put it in place of `Harness.app` and change what `harness-run.sh` runs. Images that old
predate Tart's guest agent, so `tart exec` and [TestVM](../TestVM)'s
`vm.sh` can't reach them, and their data volume is encrypted, so nothing
can be put on their disk from the Mac. A person starts the run inside the
VM instead, with one double-click.

Cirrus Labs' `macos-sequoia-vanilla:15.0` tag is a beta (24A5289g, on which
the harness gave no captures); `15.0-rc` is macOS 15.0.1 (24A348), the
earliest release they publish.

## What it does

1. On the Mac: make the VM, copy the app (built in the TestVM VM, with the
   newest SDK, so the old VM needs no Xcode) and this folder's two scripts
   into the shared transfer folder, and start the VM with it:

   ```bash
   tart clone ghcr.io/cirruslabs/macos-sequoia-vanilla:15.0-rc autohush-150
   cp -R Harness/Harness.app DevTools/OldMacVM/harness-run.sh "DevTools/OldMacVM/Run in VM.command" ~/Applications/Tart/transfer/vm15/
   tart run autohush-150 --no-audio --dir=transfer:$HOME/Applications/Tart/transfer
   ```

2. In the VM (it logs in by itself): Finder → My Shared Files → transfer →
   vm15, double-click **Run in VM.command**. It copies the app to the VM's
   disk and runs [`harness-run.sh`](harness-run.sh): the harness's menu,
   Settings pages, welcome, Add a Web App and learning windows, and a check
   that AutoHush is in the Dock only while a window is open, each capture
   taken of its own window (`SELFCAPTURE=1`,
   so no Screen Recording permission is needed), the captures copied back
   to `vm15/captures` on the Mac, and the last window left open to try by
   hand. macOS may first ask whether Terminal can open files on the shared
   folder: Allow.
