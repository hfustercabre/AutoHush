# Homebrew cask for AutoHush. Scripts/release.sh updates version and sha256.
#
# Install from this repository:
#   brew tap hfustercabre/autohush https://github.com/hfustercabre/AutoHush
#   brew install --cask autohush
cask "autohush" do
  version "0.2.0"
  sha256 "3734f1d82e143134aa8048bf634a23448438c0792889f75b97235409df1b4d23"

  url "https://github.com/hfustercabre/AutoHush/releases/download/v#{version}/AutoHush-#{version}.dmg"
  name "AutoHush"
  desc "Pauses your music while other apps play audio and resumes it afterwards"
  homepage "https://github.com/hfustercabre/AutoHush"

  # AutoHush installs its own updates, so `brew upgrade` leaves it alone
  # (unless --greedy).
  auto_updates true
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
