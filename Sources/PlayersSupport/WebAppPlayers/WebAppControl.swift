import Foundation
import os
import AutoHushKit

/// Everything `SafariWebAppPlayer` does with the web app's page, run on the
/// player's own queue, one call at a time (Accessibility calls block).
///
/// Once it knows the button (`PlayPauseRecipe`), the music's state is what
/// the button says: a read of one element, which the page answers. The state
/// observer's reads, about once a second, ask it less while the web app is
/// silent (`polledState`). After a reload every element is new, so the
/// button is looked for again. While it doesn't know the button, it learns
/// it from the user saying when the music plays, and the page once paused:
/// AutoHush pauses it itself with the keyboard's Play/Pause key, or, when
/// that doesn't take, the user does and says so (`PlayPauseLearner`).
/// Meanwhile it reports the music as playing while the app's sound is on.
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
    /// button's words (YouTube Music: within 3 s, measured), how often it's
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

    let name: String
    let bundleID: String
    let page: any WebPage
    let store: any PlayPauseRecipeStore
    let clock: @Sendable () -> Date
    let sleep: @Sendable (TimeInterval) -> Void
    let status: LearningStatusBroadcast
    let muter: any AudioMuting
    private let levelProbe: any AudioLevelProbing
    /// Whether muting may stand in for a pause now (not in AntiDot mode).
    let mayMute: @Sendable () -> Bool
    /// Presses the keyboard's Play/Pause key (`PlayPauseKey`).
    let pressKey: @Sendable () -> Void
    let logger = AutoHushLogger(category: "WebAppPlayer")

    var recipe: PlayPauseRecipe?
    /// The learned button, as last found.
    var button: ButtonHandle?
    /// Learning, when there's no recipe or the button went missing.
    var learner: PlayPauseLearner?
    /// The user asked to learn it again: the recipe stays, and controls it,
    /// until they say it plays (`notePlaying`); it's forgotten only then.
    var relearning = false
    /// Since when the web app is heard without the learned button.
    var missingSince: Date?
    var noWindowUntil: Date?
    var noWindowWait = WebAppControl.noWindowPause
    var otherWindowsCheckedAt: Date?
    /// The state the button last gave, for which app, and when.
    var lastRead: (state: PlayerState, pid: pid_t, at: Date)?

    /// Why the web app was muted instead of paused.
    enum MuteReason {
        /// Its button was disabled (an ad): nothing was pressed.
        case buttonDisabled
        /// A press didn't take in time; it may still pause the page later.
        case pressIgnored
        /// A press couldn't be made: nothing was pressed.
        case pressFailed
        /// Its button said it was paused while it could be heard (an ad).
        case playsAnyway
        /// AutoHush no longer holds the pause (the Mac slept): lifted once
        /// the page is paused for real, or silent.
        case forgotten
    }

    /// The web app muted in place of a pause, by its pid.
    var muted: (pid: pid_t, reason: MuteReason)?

    /// What a look for the learned button found.
    enum Lookup {
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
        mayMute: @escaping @Sendable () -> Bool,
        pressKey: @escaping @Sendable () -> Void,
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
                // A Chromium or Flutter page out of sight keeps an old word: its sound tells instead.
                guard page.wordsAreCurrent(pid: pid) else { return page.isPlayingSound(pid: pid) ? .playing : .paused }
                let state = Self.state(of: found, recipe: recipe)
                if state == .playing || state == .paused { page.noteState(playing: state == .playing, pid: pid) }
                return state
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
            if state == .playing, mute(pid: pid, reason: .pressFailed) { return }
            throw MusicPlayerError.playerCommandFailed(.pressFailed)
        }
        if follows(button, recipe: recipe, from: state, pid: pid) { return }
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
    func forgetLearned() {
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

    /// How long before asking once more which app is Now Playing, when
    /// another app (or none) holds it: an app takes Now Playing as its sound
    /// starts, and the user may click It's Playing right then.
    static let nowPlayingRecheck: TimeInterval = 0.5

    static let keyLogger = AutoHushLogger(category: "WebAppPlayer")
}
