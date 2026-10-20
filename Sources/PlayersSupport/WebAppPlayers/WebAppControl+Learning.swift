import Foundation
import os
import AutoHushKit

// WebAppControl: learning the Play/Pause button as the user says.
extension WebAppControl {
    /// The user says the music itself plays: the page is looked at, to
    /// compare once they've paused it. Only while the web app can be heard,
    /// and its page read (`pid` is `nil` while it isn't running). Learning
    /// again, what it learned is forgotten once this is taken.
    func notePlaying(pid: pid_t?) -> LearningMark {
        guard learner != nil || relearning else { return .notLearning }
        guard let pid else { return .cantSeePage }
        // Heard first: a click while it's silent costs no read of the page.
        guard page.isPlayingSound(pid: pid) else { return .notHeard }
        guard let buttons = readablePage(pid: pid) else { return .cantSeePage }
        if relearning { forgetLearned() }
        var learner = self.learner ?? PlayPauseLearner()
        learner.notePlaying(buttons, at: clock())
        self.learner = learner
        logger.notice("\(self.name, privacy: .public) plays, the user says: its page is noted (\(buttons.count, privacy: .public) buttons)")
        status.send(.learning(hasPlayed: true))
        return .noted
    }

    /// Whether the keyboard's Play/Pause key would reach the app `pid`: macOS
    /// sends it to the app it counts as playing now ("Now Playing"), here a
    /// helper the web app is responsible for. `false` when another app, or
    /// none, holds it, asked twice `nowPlayingRecheck` apart; `true` when it
    /// does, or when that can't be told (`.unknown`: the key is pressed as
    /// ever). `nowPlaying` blocks (a fresh process answers): never on a
    /// player's queue.
    static func keyReaches(pid: pid_t?, nowPlaying: () -> NowPlayingApp.Answer,
                           sleep: (TimeInterval) -> Void) -> Bool {
        guard let pid else { return true } // nothing is pressed without it anyway
        func reaches(_ answer: NowPlayingApp.Answer) -> Bool {
            switch answer {
            case .process(let holder): ProcessResponsibility.isOwned(holder, by: pid)
            case .none: false
            case .unknown: true
            }
        }
        if reaches(nowPlaying()) { return true }
        sleep(nowPlayingRecheck)
        let answer = nowPlaying()
        guard !reaches(answer) else { return true }
        switch answer {
        case .process(let holder): keyLogger.notice("Another app is Now Playing (pid \(holder, privacy: .public)), not the web app")
        default: keyLogger.notice("No app is Now Playing")
        }
        return false
    }

    /// Right after the user said it plays: AutoHush pauses it itself, with
    /// the keyboard's Play/Pause key, learns the button whose words changed,
    /// and plays it again with that button. When the key wouldn't reach it
    /// (`keyReaches`, false: another app is Now Playing, or none), it isn't
    /// pressed at all: `.keyGoesElsewhere`. The site can still ignore it:
    /// with no change within `keyWait` the key is pressed again, to undo
    /// whatever it did (`.didntTake`). Either way the user pauses it and says
    /// so (`notePaused`).
    func pauseByItself(pid: pid_t?, keyReaches: Bool = true) -> SelfPause {
        guard let learner, learner.hasPlayed, let pid else { return .didntTake }
        guard keyReaches else {
            logger.notice("\(self.name, privacy: .public) is paused by the user, not the Play/Pause key, which would reach another app")
            return .keyGoesElsewhere
        }
        pressKey()
        let deadline = clock().addingTimeInterval(Self.keyWait)
        repeat {
            sleep(Self.keyCheckInterval)
            // The page was read at It's Playing: no first look to wait for.
            guard let buttons = readablePage(pid: pid, looksAgain: false),
                  !learner.candidates(paused: buttons).isEmpty else { continue }
            sleep(Self.keySettle)
            guard let settled = readablePage(pid: pid, looksAgain: false), learn(from: settled) else { continue }
            logger.notice("\(self.name, privacy: .public) paused for the Play/Pause key: playing it again")
            do {
                try press(from: .paused, pid: pid)
            } catch {
                logger.error("Playing \(self.name, privacy: .public) again failed: \(error)")
                pressKey()
            }
            return .paused
        } while clock() < deadline
        pressKey()
        logger.notice("\(self.name, privacy: .public)’s page didn’t change for the Play/Pause key: the user pauses it")
        return .didntTake
    }

    /// The user says they paused it: the button whose words changed since
    /// it played is learned (see `PlayPauseLearner`), keeping the places
    /// learned before.
    func notePaused(pid: pid_t?) -> LearningMark {
        guard var learner, learner.hasPlayed else { return .notLearning }
        let tooLate = learner.playedTooLongAgo(at: clock())
        guard !tooLate, let pid, let buttons = readablePage(pid: pid) else {
            // Back to the first step: it played too long ago, or its page went.
            learner.forgetPlaying()
            self.learner = learner
            status.send(.learning(hasPlayed: false))
            return tooLate ? .tooLate : .cantSeePage
        }
        if learn(from: buttons) { return .noted }
        logger.notice("\(self.name, privacy: .public) was paused, the user says, but no button changed")
        return .nothingChanged
    }

    /// Learns the button whose words changed between the look while it
    /// played and `buttons`, keeping the places learned before. `false` when
    /// none did.
    func learn(from buttons: [PageButton]) -> Bool {
        guard let learner, learner.hasPlayed else { return false }
        let found = learner.candidates(paused: buttons)
        let candidates = found.compactMap { candidate -> (PlayPauseLearner.Candidate, ButtonPlace, ButtonStanding)? in
            guard let place = page.place(of: candidate.handle) else { return nil }
            return (candidate, place, page.standing(of: candidate.handle) ?? ButtonStanding())
        }
        // Where each candidate was (none: its place couldn't be read), never its words.
        let places = found.map { candidate in
            candidates.first { $0.0 == candidate }.map { _, place, standing in
                "\(Int(place.distanceFromBottom)) pt" + (standing.isInWindow ? "" : " out of sight")
                    + (standing.isWithPlayerControls ? " with controls" : "")
            } ?? "none"
        }
        logger.debug("Learning: \(found.count, privacy: .public) buttons changed, at \(places.joined(separator: ", "), privacy: .public)")
        guard let (learned, handle) = PlayPauseLearner.recipe(from: candidates) else { return false }
        let merged = recipe?.merging(learned) ?? learned
        recipe = merged
        button = handle
        missingSince = nil
        lastRead = nil
        self.learner = nil
        store.save(merged, for: bundleID)
        logger.notice("Learned \(self.name, privacy: .public)’s Play/Pause button")
        status.send(.learned)
        return true
    }

    /// The page's buttons, unless it has no window or none of its buttons
    /// has words: a window macOS restores at login can show its buttons
    /// without their words (measured). A small page with a few named
    /// buttons is read. Seen without words, it's looked at once more
    /// after `firstLookWait` (`looksAgain`), in case that was its first look.
    private func readablePage(pid: pid_t, looksAgain: Bool = true) -> [PageButton]? {
        func look() -> [PageButton]? {
            guard let buttons = page.buttons(pid: pid), buttons.contains(where: { !$0.label.isEmpty }) else { return nil }
            return buttons
        }
        if let buttons = look() { return buttons }
        // Maybe the page's first look ever (see `firstLookWait`): once more.
        guard looksAgain, page.hasWindow(pid: pid) else { return nil }
        sleep(Self.firstLookWait)
        return look()
    }

    /// The pause didn't come in time, or the look while it plays couldn't be
    /// taken again (Try Again, Pause It Yourself): back to waiting for the
    /// user to say it plays. `false` when it wasn't waiting for the pause.
    func restartLearning() -> Bool {
        guard var learner, learner.hasPlayed else { return false }
        learner.forgetPlaying()
        self.learner = learner
        logger.notice("\(self.name, privacy: .public)’s learning goes back to It’s Playing")
        status.send(.learning(hasPlayed: false))
        return true
    }

    /// Lifts a mute, without playing anything: monitoring stops.
    func releaseMute() {
        guard let muted else { return }
        self.muted = nil
        muter.unmute(appPID: muted.pid)
    }
}
