import Foundation
import OSLog
import os
import AutoHushKit

/// Everything `SafariWebAppPlayer` does with the web app's page, run on the
/// player's own queue, one call at a time (Accessibility calls block).
///
/// Once it knows the button (`PlayPauseRecipe`), the music's state is what
/// the button says: a read of one element, which the page answers. The state
/// observer's reads, about once a second, ask it less while the web app is
/// silent (`polledState`). After a reload every element is new, so the
/// button is looked for again. While it doesn't know
/// the button, it learns it from the user saying when the music plays, and
/// the page once paused: AutoHush pauses it itself with the keyboard's
/// Play/Pause key, or, when that doesn't take, the user does and says so
/// (`PlayPauseLearner`). Meanwhile it reports the music as playing while
/// the app's sound is on.
///
/// When the web app is heard but the button can't be found for a minute
/// (the site changed), it learns again, keeping what it knew: if the button
/// turns up again, it stops learning. A silent page isn't missing it: a fresh
/// YouTube Music window shows its player bar only once something plays.
///
/// Each window of the web app has its own page, so with two windows there are
/// two buttons in the same place: the one that says the music plays is
/// followed, also when the music moves to the other window.
///
/// A site may refuse to pause: it disables its button during an ad, or a
/// press doesn't take. Only then is the web app muted instead (`AudioMuting`)
/// and reported as paused, until it's played again or monitoring stops. So
/// is a site whose button says it's paused while it can be heard (YouTube
/// Music during an ad). Once the site lets itself be paused (the ad is over,
/// the music plays), it's paused for real and heard again: played later, it
/// goes on from there.
final class WebAppControl: @unchecked Sendable {
    /// After a look finds no window, the next one waits this long, and twice
    /// as long after each look that finds none, up to `noWindowPauseLimit`:
    /// looking for windows on other Spaces tries a thousand elements. A web
    /// app whose sound is on is looked at at once.
    static let noWindowPause: TimeInterval = 5
    static let noWindowPauseLimit: TimeInterval = 60
    /// While the web app is silent and its button last said it isn't playing,
    /// the state observer's reads reuse that for this long: each read asks the
    /// page, which costs the web app some work (measured: as much as AutoHush's
    /// own). Its sound coming on reads the button at once.
    static let quietReadInterval: TimeInterval = 5
    /// The button missing this long from a page that's heard starts learning.
    static let missingBeforeLearning: TimeInterval = 60
    /// A page with fewer buttons is still loading (or asks to log in).
    static let loadedPageButtons = 10
    /// After a press, how long the button gets to change its words.
    static let pressConfirmation: TimeInterval = 2
    static let pressCheckInterval: TimeInterval = 0.1
    /// While the button says the music isn't playing, how often the other
    /// windows are checked for one that plays.
    static let otherWindowsInterval: TimeInterval = 2
    /// After the Play/Pause key, how long the page gets to change its
    /// button's words (YouTube Music in the VM: within 3 s), how often it's
    /// read meanwhile, and how long a change gets to settle: a song's own
    /// button can change before the player bar's.
    static let keyWait: TimeInterval = 3
    static let keyCheckInterval: TimeInterval = 0.5
    static let keySettle: TimeInterval = 0.5
    /// How long a page that answered a look with nothing gets before it's
    /// looked at again: WebKit builds a page for Accessibility at the first
    /// question about it, and answers that one with no buttons (measured on
    /// a web app just opened: the next look, 0.1 s later, finds them all).
    static let firstLookWait: TimeInterval = 0.3

    private let name: String
    private let bundleID: String
    private let page: any WebPage
    private let store: any PlayPauseRecipeStore
    private let clock: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) -> Void
    private let status: LearningStatusBroadcast
    private let muter: any AudioMuting
    private let levelProbe: any AudioLevelProbing
    /// Whether muting may stand in for a pause now (not in AntiDot mode).
    private let mayMute: @Sendable () -> Bool
    /// Presses the keyboard's Play/Pause key (`PlayPauseKey`).
    private let pressKey: @Sendable () -> Void
    private let logger = Logger(category: "WebAppPlayer")

    private var recipe: PlayPauseRecipe?
    /// The learned button, as last found.
    private var button: ButtonHandle?
    /// Learning, when there's no recipe or the button went missing.
    private var learner: PlayPauseLearner?
    /// The user asked to learn it again: the recipe stays, and controls it,
    /// until they say it plays (`notePlaying`); it's forgotten only then.
    private var relearning = false
    /// Since when the web app is heard without the learned button.
    private var missingSince: Date?
    private var noWindowUntil: Date?
    private var noWindowWait = WebAppControl.noWindowPause
    private var otherWindowsCheckedAt: Date?
    /// The state the button last gave, for which app, and when.
    private var lastRead: (state: PlayerState, pid: pid_t, at: Date)?

    /// Why the web app was muted instead of paused.
    private enum MuteReason {
        /// Its button was disabled (an ad): nothing was pressed.
        case buttonDisabled
        /// A press didn't take in time; it may still pause the page later.
        case pressIgnored
        /// Its button said it was paused while it could be heard (an ad).
        case playsAnyway
        /// AutoHush no longer holds the pause (the Mac slept): lifted once
        /// the page is paused for real, or silent.
        case forgotten
    }

    /// The web app muted in place of a pause, by its pid.
    private var muted: (pid: pid_t, reason: MuteReason)?

    /// What a look for the learned button found.
    private enum Lookup {
        case found(PageButton)
        case noWindow
        /// `buttons`: the page's, when it was looked at.
        case missing(buttons: [PageButton]?)
    }

    init(
        name: String,
        bundleID: String,
        page: any WebPage,
        store: any PlayPauseRecipeStore,
        status: LearningStatusBroadcast,
        muter: any AudioMuting,
        levelProbe: any AudioLevelProbing,
        mayMute: @escaping @Sendable () -> Bool = { true },
        pressKey: @escaping @Sendable () -> Void = {},
        clock: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (TimeInterval) -> Void
    ) {
        self.name = name
        self.bundleID = bundleID
        self.page = page
        self.store = store
        self.status = status
        self.muter = muter
        self.levelProbe = levelProbe
        self.mayMute = mayMute
        self.pressKey = pressKey
        self.clock = clock
        self.sleep = sleep
        recipe = store.recipe(for: bundleID)
        if recipe == nil { learner = PlayPauseLearner() }
        status.send(recipe == nil ? .learning(hasPlayed: false) : .learned)
    }

    /// The music's state in the app running as `pid`. Learns meanwhile.
    func state(pid: pid_t) -> PlayerState {
        let state = readState(pid: pid)
        lastRead = (state, pid, clock())
        return state
    }

    /// The state, for the observer that reads it about once a second: while
    /// the web app is silent and its button last said it isn't playing (or
    /// couldn't be found, or it's learning and isn't heard), with nothing
    /// muted, that's reused for `quietReadInterval`. Before deciding,
    /// AutoHush reads `state` afresh.
    func polledState(pid: pid_t) -> PlayerState {
        if let lastRead, lastRead.pid == pid, [.paused, .stopped, .unknown].contains(lastRead.state),
           muted == nil,
           clock().timeIntervalSince(lastRead.at) < Self.quietReadInterval,
           !page.isPlayingSound(pid: pid) {
            return lastRead.state
        }
        return state(pid: pid)
    }

    private func readState(pid: pid_t) -> PlayerState {
        if let muted {
            if muted.pid == pid { // muted in place of a pause
                if muted.reason != .pressIgnored { pauseOnceItCan(pid: pid) }
                return .paused
            }
            releaseMute() // the app was opened again since
        }
        let now = clock()
        var hasWindow = true
        if let recipe {
            switch lookup(recipe, pid: pid, now: now) {
            case .found(let found):
                missingSince = nil
                if learner != nil {
                    learner = nil
                    logger.notice("\(self.name, privacy: .public)'s Play/Pause button is back")
                    status.send(relearning ? .relearning : .learned)
                }
                return Self.state(of: found, recipe: recipe)
            case .noWindow:
                hasWindow = false
            case .missing(let looked):
                noteMissing(buttons: looked, pid: pid, at: now)
            }
        }
        guard learner != nil else { return hasWindow ? .unknown : .stopped }
        // Learning needs no look at the page until the user says so. Heard,
        // it plays; silent, whether it has a window is enough (known already
        // when it looked for the button).
        if page.isPlayingSound(pid: pid) { return .playing }
        if recipe == nil { hasWindow = windowShows(pid: pid, now: now) }
        return hasWindow ? .paused : .stopped
    }

    /// Presses the button if the music is in `state`; does nothing if it's
    /// already in the other one. Throws when the button can't be pressed, or
    /// the page doesn't follow. A pause the site refuses mutes the web app
    /// instead; playing it again unmutes it.
    func press(from state: PlayerState, pid: pid_t) throws {
        if state == .paused, muted != nil {
            try unmute(pid: pid)
            return
        }
        let current = self.state(pid: pid)
        guard current == state else {
            if current == .unknown { throw MusicPlayerError.playerCommandFailed(.stateUnknown) }
            if current == .stopped { throw MusicPlayerError.playerCommandFailed(.nothingToPlay) }
            return
        }
        guard learner == nil, let recipe, let button else { throw MusicPlayerError.stillLearning }
        // Sites disable it while they can't be paused, such as during an ad.
        guard page.button(button)?.isEnabled == true else {
            logger.notice("\(self.name, privacy: .public)'s Play/Pause is disabled: not pressed")
            if state == .playing, mute(pid: pid, reason: .buttonDisabled) { return }
            throw MusicPlayerError.playerCommandFailed(.buttonDisabled)
        }
        guard page.press(button) else {
            logger.error("Pressing \(self.name, privacy: .public)'s Play/Pause failed")
            throw MusicPlayerError.playerCommandFailed(.pressFailed)
        }
        if follows(button, recipe: recipe, from: state) { return }
        logger.error("\(self.name, privacy: .public)'s Play/Pause didn't change after a press")
        if state == .playing, mute(pid: pid, reason: .pressIgnored) { return }
        throw MusicPlayerError.playerCommandFailed(.pressIgnored)
    }

    /// The button says the music is paused (or can't play) while the web app
    /// can be heard: an ad its site won't let be paused, as YouTube Music's,
    /// whose Play/Pause reads "Play" meanwhile. Mutes it then, as for a
    /// refused pause; `false` when it's silent or can't be muted. Its level is
    /// measured, since a page keeps its output open, silent, for seconds
    /// after a pause.
    func muteIfPlayingAnyway(pid: pid_t) -> Bool {
        if let muted { return muted.pid == pid && muted.reason != .forgotten }
        guard mayMute(), learner == nil, [.paused, .stopped].contains(state(pid: pid)),
              page.isPlayingSound(pid: pid) else { return false }
        guard levelProbe.isAudible(appPID: pid) else {
            logger.debug("\(self.name, privacy: .public)'s sound is open but silent: not muted")
            return false
        }
        return mute(pid: pid, reason: .playsAnyway)
    }

    /// AutoHush no longer holds the pause a mute stands in for (the Mac
    /// slept): the web app stays muted only until it's paused for real, or
    /// silent, and isn't played again.
    func forgetPause() {
        guard let muted else { return }
        self.muted = (muted.pid, .forgotten)
    }

    /// Learns the button afresh from the user playing and pausing the web
    /// app once: the user asked, as it may have been learned wrong. What it
    /// learned stays, and is pressed, until they say it plays (a click by
    /// mistake costs nothing); it's forgotten then (`forgetLearned`). Never
    /// learned, learning starts over.
    func learnAgain() {
        lastRead = nil
        guard recipe != nil else {
            learner = PlayPauseLearner()
            logger.notice("Learning \(self.name, privacy: .public)'s Play/Pause button from the start, as asked")
            status.send(.learning(hasPlayed: false))
            return
        }
        relearning = true
        logger.notice("Learning \(self.name, privacy: .public)'s Play/Pause button again, as asked: kept until it plays")
        if learner != nil { // the button had gone missing: that learning starts over
            learner = PlayPauseLearner()
            status.send(.learning(hasPlayed: false))
        } else {
            status.send(.relearning)
        }
    }

    /// The user left learning again before saying it plays (the learning
    /// window was closed): what it learned stays.
    func keepLearned() {
        guard relearning else { return }
        relearning = false
        logger.notice("\(self.name, privacy: .public) keeps the Play/Pause button it learned")
        if learner == nil { status.send(.learned) }
    }

    /// Learning again, the user says it plays: what it learned goes, so
    /// nothing of a wrong one is kept, and a mute standing in for a pause is
    /// lifted (nothing is pressed until it's learned).
    private func forgetLearned() {
        relearning = false
        releaseMute()
        recipe = nil
        button = nil
        missingSince = nil
        lastRead = nil
        store.forget(for: bundleID)
        logger.notice("\(self.name, privacy: .public)'s learned Play/Pause button is forgotten: learning it again")
    }

    // MARK: - Learning, as the user says

    /// The user says the music itself plays: the page is looked at, to
    /// compare once they've paused it. Only while the web app can be heard,
    /// and its page read (`pid` is `nil` while it isn't running). Learning
    /// again, what it learned is forgotten once this is taken.
    func notePlaying(pid: pid_t?) -> LearningMark {
        guard learner != nil || relearning else { return .notLearning }
        guard let pid, let buttons = readablePage(pid: pid) else { return .cantSeePage }
        guard page.isPlayingSound(pid: pid) else { return .notHeard }
        if relearning { forgetLearned() }
        var learner = self.learner ?? PlayPauseLearner()
        learner.notePlaying(buttons, at: clock())
        self.learner = learner
        logger.notice("\(self.name, privacy: .public) plays, the user says: its page is noted (\(buttons.count, privacy: .public) buttons)")
        status.send(.learning(hasPlayed: true))
        return .noted
    }

    /// Right after the user said it plays: AutoHush pauses it itself, with
    /// the keyboard's Play/Pause key, learns the button whose words changed,
    /// and plays it again with that button. macOS sends the key to the app it
    /// counts as playing now: the web app, while its song plays, but it can
    /// be another (one that played last), or the site can ignore it. With no
    /// change within `keyWait` the key is pressed again, to undo whatever it
    /// did, and `false` says the user pauses it and says so (`notePaused`).
    func pauseByItself(pid: pid_t?) -> Bool {
        guard let learner, learner.hasPlayed, let pid else { return false }
        pressKey()
        let deadline = clock().addingTimeInterval(Self.keyWait)
        repeat {
            sleep(Self.keyCheckInterval)
            guard let buttons = readablePage(pid: pid), !learner.candidates(paused: buttons).isEmpty else { continue }
            sleep(Self.keySettle)
            guard let settled = readablePage(pid: pid), learn(from: settled) else { continue }
            logger.notice("\(self.name, privacy: .public) paused for the Play/Pause key: playing it again")
            do {
                try press(from: .paused, pid: pid)
            } catch {
                logger.error("Playing \(self.name, privacy: .public) again failed: \(error.localizedDescription, privacy: .public)")
                pressKey()
            }
            return true
        } while clock() < deadline
        pressKey()
        logger.notice("\(self.name, privacy: .public)'s page didn't change for the Play/Pause key: the user pauses it")
        return false
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
    private func learn(from buttons: [PageButton]) -> Bool {
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
        logger.notice("Learned \(self.name, privacy: .public)'s Play/Pause button")
        status.send(.learned)
        return true
    }

    /// The page's buttons, unless it has no window or none of its buttons
    /// has words: a window macOS restores at login can show its buttons
    /// without their words (measured in the VM). A small page with a few
    /// named buttons is read.
    private func readablePage(pid: pid_t) -> [PageButton]? {
        func look() -> [PageButton]? {
            guard let buttons = page.buttons(pid: pid), buttons.contains(where: { !$0.label.isEmpty }) else { return nil }
            return buttons
        }
        if let buttons = look() { return buttons }
        // Maybe the page's first look ever (see `firstLookWait`): once more.
        guard page.hasWindow(pid: pid) else { return nil }
        sleep(Self.firstLookWait)
        return look()
    }

    /// The pause didn't come in time, or the look while it plays couldn't be
    /// taken again (Try Again, Pause It Manually): back to waiting for the
    /// user to say it plays. `false` when it wasn't waiting for the pause.
    func restartLearning() -> Bool {
        guard var learner, learner.hasPlayed else { return false }
        learner.forgetPlaying()
        self.learner = learner
        logger.notice("\(self.name, privacy: .public)'s learning goes back to It's Playing")
        status.send(.learning(hasPlayed: false))
        return true
    }

    /// Lifts a mute, without playing anything: monitoring stops.
    func releaseMute() {
        guard let muted else { return }
        self.muted = nil
        muter.unmute(appPID: muted.pid)
    }

    // MARK: - Muting in place of a pause

    /// Mutes the web app since it refused to pause; `false` when it couldn't.
    private func mute(pid: pid_t, reason: MuteReason) -> Bool {
        guard mayMute(), muter.mute(appPID: pid) else { return false }
        muted = (pid, reason)
        if reason == .playsAnyway {
            logger.notice("\(self.name, privacy: .public) plays while its button says it's paused: muted instead")
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
    private func pauseOnceItCan(pid: pid_t) {
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
        guard follows(found.handle, recipe: recipe, from: .playing) else {
            if forgotten { releaseMute() } else { muted = (pid, .pressIgnored) }
            return
        }
        logger.notice("\(self.name, privacy: .public) can be paused now: paused, and no longer muted")
        releaseMute()
    }

    /// Whether the button's words changed from `state` within `pressConfirmation`.
    private func follows(_ button: ButtonHandle, recipe: PlayPauseRecipe, from state: PlayerState) -> Bool {
        let deadline = clock().addingTimeInterval(Self.pressConfirmation)
        repeat {
            if let now = page.button(button), let shown = recipe.state(of: now), shown != state { return true }
            sleep(Self.pressCheckInterval)
        } while clock() < deadline
        return false
    }

    /// Lets the web app be heard again. If the press that didn't take paused
    /// the page after all, it's played again; if the user paused it during an
    /// ad, it's left paused.
    private func unmute(pid: pid_t) throws {
        guard let muted else { return }
        releaseMute()
        guard muted.reason == .pressIgnored, muted.pid == pid, state(pid: pid) == .paused else { return }
        try press(from: .paused, pid: pid)
    }

    // MARK: - The learned button

    /// The learned button. With two windows of the web app there are two, in
    /// the same place: the one that says the music plays wins.
    private func lookup(_ recipe: PlayPauseRecipe, pid: pid_t, now: Date) -> Lookup {
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
    private static func playing(in buttons: [PageButton], recipe: PlayPauseRecipe,
                                place: (ButtonHandle) -> ButtonPlace?) -> PageButton? {
        recipe.find(in: buttons.filter { recipe.state(of: $0) == .playing }, place: place)
    }

    /// The page's buttons; `nil` while the app has no window, and for a
    /// while after a look found none (longer each time), unless its sound is
    /// on.
    private func look(pid: pid_t, now: Date) -> [PageButton]? {
        guard mayLookForWindows(pid: pid, now: now) else { return nil }
        let buttons = page.buttons(pid: pid)
        noteWindow(shows: buttons != nil, at: now)
        return buttons
    }

    /// Whether the app has a window, without reading its page; `false` for a
    /// while after a look found none, as for `look`.
    private func windowShows(pid: pid_t, now: Date) -> Bool {
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
    private func noteMissing(buttons: [PageButton]?, pid: pid_t, at now: Date) {
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

/// A learning status, readable from any thread, and sent to everyone
/// listening when it changes.
final class LearningStatusBroadcast: Sendable {
    private struct State {
        var current: LearningStatus = .learning(hasPlayed: false)
        var listeners: [UUID: AsyncStream<LearningStatus>.Continuation] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var current: LearningStatus { state.withLock { $0.current } }

    /// Tells the listeners, if it changed. They're told under the lock, so
    /// a listener added meanwhile can't get an older status after this one.
    func send(_ status: LearningStatus) {
        state.withLock { state in
            guard state.current != status else { return }
            state.current = status
            state.listeners.values.forEach { $0.yield(status) }
        }
    }

    /// The status now, then each change.
    func updates() -> AsyncStream<LearningStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: LearningStatus.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        state.withLock { state in
            state.listeners[id] = continuation
            continuation.yield(state.current)
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.listeners.removeValue(forKey: id) }
        }
        return stream
    }
}
