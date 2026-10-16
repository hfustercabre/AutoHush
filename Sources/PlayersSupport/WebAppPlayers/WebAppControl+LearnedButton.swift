import Foundation
import os
import AutoHushKit

// WebAppControl: pressing the learned button.
extension WebAppControl {
    /// The learned button. With two windows of the web app there are two, in
    /// the same place: the one that says the music plays wins.
    func lookup(_ recipe: PlayPauseRecipe, pid: pid_t, now: Date) -> Lookup {
        if let button, let found = page.button(button), let shown = recipe.state(of: found) {
            if shown != .playing, let other = playingElsewhere(recipe, pid: pid, now: now) {
                logger.notice("\(self.name, privacy: .public) plays in another window: following its Play/Pause")
                self.button = other.handle
                return .found(other)
            }
            return .found(found)
        }
        button = nil
        guard let buttons = look(pid: pid, now: now) else { return .noWindow }
        guard let found = Self.playing(in: buttons, recipe: recipe, place: page.place(of:))
            ?? recipe.find(in: buttons, place: page.place(of:)) else { return .missing(buttons: buttons) }
        button = found.handle
        return .found(found)
    }

    /// Another window's button saying the music plays, while the one known
    /// says it doesn't and the web app can be heard: the user plays it in a
    /// second window. Looked for every `otherWindowsInterval` at most.
    private func playingElsewhere(_ recipe: PlayPauseRecipe, pid: pid_t, now: Date) -> PageButton? {
        if let checked = otherWindowsCheckedAt, now.timeIntervalSince(checked) < Self.otherWindowsInterval { return nil }
        otherWindowsCheckedAt = now
        guard page.isPlayingSound(pid: pid), let buttons = look(pid: pid, now: now) else { return nil }
        return Self.playing(in: buttons, recipe: recipe, place: page.place(of:))
    }

    /// The learned button among `buttons` that says the music plays.
    static func playing(in buttons: [PageButton], recipe: PlayPauseRecipe,
                                place: (ButtonHandle) -> ButtonPlace?) -> PageButton? {
        recipe.find(in: buttons.filter { recipe.state(of: $0) == .playing }, place: place)
    }

    /// The page's buttons; `nil` while the app has no window, and for a
    /// while after a look found none (longer each time), unless its sound is
    /// on.
    func look(pid: pid_t, now: Date) -> [PageButton]? {
        guard mayLookForWindows(pid: pid, now: now) else { return nil }
        let buttons = page.buttons(pid: pid)
        noteWindow(shows: buttons != nil, at: now)
        return buttons
    }

    /// Whether the app has a window, without reading its page; `false` for a
    /// while after a look found none, as for `look`.
    func windowShows(pid: pid_t, now: Date) -> Bool {
        guard mayLookForWindows(pid: pid, now: now) else { return false }
        let shows = page.hasWindow(pid: pid)
        noteWindow(shows: shows, at: now)
        return shows
    }

    private func mayLookForWindows(pid: pid_t, now: Date) -> Bool {
        guard let noWindowUntil, now < noWindowUntil else { return true }
        return page.isPlayingSound(pid: pid)
    }

    /// After a look that found no window, the next one waits, longer each time.
    private func noteWindow(shows: Bool, at now: Date) {
        if shows {
            noWindowUntil = nil
            noWindowWait = Self.noWindowPause
        } else {
            noWindowUntil = now.addingTimeInterval(noWindowWait)
            noWindowWait = min(noWindowWait * 2, Self.noWindowPauseLimit)
        }
    }

    /// Starts learning again once the button has been missing for long from
    /// a page that has loaded, while the web app is heard all along: a page
    /// that doesn't play may not show its player at all.
    func noteMissing(buttons: [PageButton]?, pid: pid_t, at now: Date) {
        guard learner == nil, let buttons, buttons.count >= Self.loadedPageButtons,
              page.isPlayingSound(pid: pid) else {
            if learner == nil { missingSince = nil }
            return
        }
        let since = missingSince ?? now
        missingSince = since
        guard now.timeIntervalSince(since) >= Self.missingBeforeLearning else { return }
        logger.notice("\(self.name, privacy: .public)'s Play/Pause button can't be found: learning it again")
        learner = PlayPauseLearner()
        status.send(.learning(hasPlayed: false))
    }

    static func state(of button: PageButton, recipe: PlayPauseRecipe) -> PlayerState {
        guard let state = recipe.state(of: button) else { return .unknown }
        // A disabled Play: nothing to play yet.
        return state == .paused && !button.isEnabled ? .stopped : state
    }
}
