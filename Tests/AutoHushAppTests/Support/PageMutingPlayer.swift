import Foundation
import AutoHushKit
import AutoHushTestSupport
import WebAppPlayers

/// A web app's page as the player, for the tests of a pause held by a mute
/// and taken back: its site refuses the pause, so its pause mutes it
/// instead, through a tap of its own, and it reads as paused while muted;
/// played, the mute is lifted. During an ad (`ad`) its button reads Play
/// while it's heard, and it says it's paused (or stopped, as `ad` says):
/// it's muted only when asked to (`muteIfPlayingAnyway`). Its observer is the web apps' own
/// `StoppingObserver`, which lifts that mute as it stops, as a web app's
/// does (S1 of 2026-11-19: the old monitoring's stop lifted the page's mute
/// the new one had taken over).
actor PageMutingPlayer: MutingMusicPlayer, FadelessMusicPlayer {
    nonisolated let bundleID: String
    nonisolated let name: String
    nonisolated var stateReportDelay: TimeInterval { 0 }
    nonisolated var checksItsPresses: Bool { true }
    private nonisolated let tap: SoundTap
    /// What it says during an ad (`.paused` or `.stopped`); `nil` with none.
    private nonisolated let ad: PlayerState?
    private nonisolated var showsAd: Bool { ad != nil }
    private nonisolated let tapsAllowed = Locked(true)
    /// The access checks still to fail, as a permission taken away.
    private nonisolated let deniedChecks = Locked(0)

    init(bundleID: String, name: String, tap: SoundTap, ad: PlayerState? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.tap = tap
        self.ad = ad
    }

    /// The next `count` access checks fail, its Accessibility permission missing.
    nonisolated func deny(_ count: Int) { deniedChecks.value = count }

    func verifyControlAccess() throws {
        let denied = deniedChecks.withLock { left in
            defer { left = max(left - 1, 0) }
            return left > 0
        }
        if denied { throw MusicPlayerError.accessibilityPermissionDenied }
    }

    /// Paused while muted, as a web app's page reads.
    func playerState() -> PlayerState { tap.isMuting ? .paused : ad ?? .playing }

    func pause() throws {
        guard !showsAd else { return } // its button says it's paused already
        guard tapsAllowed.value, tap.mute(appPID: 0) else { throw MusicPlayerError.playerCommandFailed(.pressIgnored) }
    }

    func play() { tap.unmute(appPID: 0) }

    func muteIfPlayingAnyway() -> Bool {
        if tap.isMuting { return true }
        guard showsAd, tapsAllowed.value else { return false }
        return tap.mute(appPID: 0)
    }

    func forgetPause() {}
    func releaseMute() { tap.unmute(appPID: 0) }
    func isMutedForPause() -> Bool { tap.isMuting }

    nonisolated func allowTaps(_ allowed: Bool) {
        tapsAllowed.value = allowed
        if !allowed { tap.unmute(appPID: 0) }
    }

    @MainActor
    func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        StoppingObserver(MockStateObserver()) { [tap] in tap.unmute(appPID: 0) }
    }
}
