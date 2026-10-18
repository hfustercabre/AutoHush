import Foundation
import os
import AutoHushKit

// WebAppControl: muting in place of a pause.
extension WebAppControl {
    /// Mutes the web app since it refused to pause; `false` when it couldn't.
    func mute(pid: pid_t, reason: MuteReason) -> Bool {
        guard mayMute(), muter.mute(appPID: pid) else { return false }
        muted = (pid, reason)
        if reason == .playsAnyway {
            logger.notice("\(self.name, privacy: .public) plays while its button says it’s paused: muted instead")
        } else {
            logger.notice("\(self.name, privacy: .public) refused to pause: muted instead")
        }
        return true
    }

    /// Muted while its site wouldn't pause: once the button lets it (the ad
    /// is over, the music plays), pauses it for real and lifts the mute, so
    /// playing it later goes on from there. A press that doesn't take leaves
    /// it muted, as for any press ignored.
    ///
    /// A pause AutoHush no longer holds (`.forgotten`) keeps it muted only
    /// while that can still end in a real pause: the mute is lifted once the
    /// page is silent, and when a press fails.
    func pauseOnceItCan(pid: pid_t) {
        guard let recipe, case .found(let found) = lookup(recipe, pid: pid, now: clock()) else { return }
        let forgotten = muted?.reason == .forgotten
        guard found.isEnabled, recipe.state(of: found) == .playing else {
            if forgotten, !page.isPlayingSound(pid: pid) { releaseMute() }
            return
        }
        guard page.press(found.handle) else {
            if forgotten { releaseMute() }
            return
        }
        guard follows(found.handle, recipe: recipe, from: .playing, pid: pid) else {
            if forgotten { releaseMute() } else { muted = (pid, .pressIgnored) }
            return
        }
        logger.notice("\(self.name, privacy: .public) can be paused now: paused, and no longer muted")
        releaseMute()
    }

    /// Whether the button's words changed from `state` within
    /// `pressConfirmation`; gone, the learned button found again tells.
    func follows(_ button: ButtonHandle, recipe: PlayPauseRecipe, from state: PlayerState, pid: pid_t) -> Bool {
        let deadline = clock().addingTimeInterval(Self.pressConfirmation)
        repeat {
            if let now = page.button(button) {
                if let shown = recipe.state(of: now), shown != state { return true }
            } else if case .found(let found) = lookup(recipe, pid: pid, now: clock()),
                      let shown = recipe.state(of: found), shown != state {
                // The site put a new button in its place (YouTube Music's Pause,
                // on macOS 14.4): the learned one, found again, tells.
                return true
            }
            sleep(Self.pressCheckInterval)
        } while clock() < deadline
        return false
    }

    /// Lets the web app be heard again. If the press that didn't take paused
    /// the page after all, it's played again; if the user paused it during an
    /// ad, it's left paused.
    func unmute(pid: pid_t) throws {
        guard let muted else { return }
        releaseMute()
        guard muted.reason == .pressIgnored, muted.pid == pid, state(pid: pid) == .paused else { return }
        try press(from: .paused, pid: pid)
    }
}
