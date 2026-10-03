# Homebrew cask for AutoHush. Scripts/release.sh updates version and sha256.
#
# Install from this repository:
#   brew tap hfustercabre/autohush https://github.com/hfustercabre/AutoHush
#   brew install --cask autohush
cask "autohush" do
  version "0.1.0"
  sha256 "85e03c54964fe79144eb31c993fbc3ec92b5ec315a5f38e7ef90b84c889064dc"

  url "https://github.com/hfustercabre/AutoHush/releases/download/v#{version}/AutoHush-#{version}.dmg"
  name "AutoHush"
  desc "Pauses your music while other apps play audio and resumes it afterwards"
  homepage "https://github.com/hfustercabre/AutoHush"

  depends_on macos: :sequoia

  app "AutoHush.app"

  # AutoHush is signed with its own certificate but not notarized by Apple,
  # so Gatekeeper would block the first launch. Installing from this tap is the
  # user's decision to trust it; drop the download quarantine accordingly.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/AutoHush.app"]
  end

  uninstall quit: "com.autohush.AutoHush"

  caveats <<~EOS
    AutoHush is not notarized by Apple; this cask removes the download
    quarantine so it opens normally.

    On first launch, allow Automation (to control Spotify) and System Audio
    Recording (to measure how loud other apps are) when macOS asks.
  EOS
end
