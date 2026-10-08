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
/// the button, it learns it (`PlayPauseLearner`), and reports the music as
/// playing while the app's sound is on.
///
/// When the page shows but the button can't be found for a minute (the site
/// changed), it learns again, keeping what it knew: if the button turns up
/// again, it stops learning.
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
    /// The button missing this long from a page that shows starts learning.
    static let missingBeforeLearning: TimeInterval = 60
    /// A page with fewer buttons is still loading (or asks to log in).
    static let loadedPageButtons = 10
    /// After a press, how long the button gets to change its words.
    static let pressConfirmation: TimeInterval = 2
    static let pressCheckInterval: TimeInterval = 0.1
    /// While the button says the music isn't playing, how often the other
    /// windows are checked for one that plays.
    static let otherWindowsInterval: TimeInterval = 2

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
    private let logger = Logger(category: "WebAppPlayer")

    private var recipe: PlayPauseRecipe?
    /// The learned button, as last found.
    private var button: ButtonHandle?
    /// Learning, when there's no recipe or the button went missing.
    private var learner: PlayPauseLearner?
    /// Since when the page shows without the learned button.
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
    /// the web app is silent and its button last said it isn't playing, with
    /// nothing to learn and nothing muted, that's reused for
    /// `quietReadInterval`. Before deciding, AutoHush reads `state` afresh.
    func polledState(pid: pid_t) -> PlayerState {
        if let lastRead, lastRead.pid == pid, lastRead.state == .paused || lastRead.state == .stopped,
           muted == nil, learner == nil,
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
        var buttons: [PageButton]?
        var hasWindow = true
        if let recipe {
            switch lookup(recipe, pid: pid, now: now) {
            case .found(let found):
                missingSince = nil
                if learner != nil {
                    learner = nil
                    logger.notice("\(self.name, privacy: .public)'s Play/Pause button is back")
                    status.send(.learned)
                }
                return Self.state(of: found, recipe: recipe)
            case .noWindow:
                hasWindow = false
            case .missing(let looked):
                buttons = looked
                noteMissing(buttons: looked, at: now)
            }
        }
        guard learner != nil else { return hasWindow ? .unknown : .stopped }
        if hasWindow, buttons == nil { buttons = look(pid: pid, now: now) }
        return learn(buttons: buttons, pid: pid, now: now)
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
            if current == .unknown || current == .stopped {
                throw MusicPlayerError.playerCommandFailed("\(name)'s state is \(current.rawValue)")
            }
            return
        }
        guard learner == nil, let recipe, let button else { throw MusicPlayerError.stillLearning }
        // Sites disable it while they can't be paused, such as during an ad.
        guard page.button(button)?.isEnabled == true else {
            logger.notice("\(self.name, privacy: .public)'s Play/Pause is disabled: not pressed")
            if state == .playing, mute(pid: pid, reason: .buttonDisabled) { return }
            throw MusicPlayerError.playerCommandFailed("\(name)'s Play/Pause button is disabled")
        }
        guard page.press(button) else {
            logger.error("Pressing \(self.name, privacy: .public)'s Play/Pause failed")
            throw MusicPlayerError.playerCommandFailed("\(name)'s Play/Pause couldn't be pressed")
        }
        if follows(button, recipe: recipe, from: state) { return }
        logger.error("\(self.name, privacy: .public)'s Play/Pause didn't change after a press")
        if state == .playing, mute(pid: pid, reason: .pressIgnored) { return }
        throw MusicPlayerError.playerCommandFailed("\(name) didn't respond to its Play/Pause button")
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

    /// Forgets the learned button, and learns it afresh from the user playing
    /// and pausing the web app once: the user asked, as it may have been
    /// learned wrong. Nothing is pressed until then, so a mute in place of a
    /// pause is lifted.
    func learnAgain() {
        releaseMute()
        recipe = nil
        button = nil
        missingSince = nil
        lastRead = nil
        store.forget(for: bundleID)
        learner = PlayPauseLearner()
        logger.notice("Learning \(self.name, privacy: .public)'s Play/Pause button again, as asked")
        status.send(.learning(hasPlayed: false))
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
        if let noWindowUntil, now < noWindowUntil, !page.isPlayingSound(pid: pid) { return nil }
        let buttons = page.buttons(pid: pid)
        if buttons == nil {
            noWindowUntil = now.addingTimeInterval(noWindowWait)
            noWindowWait = min(noWindowWait * 2, Self.noWindowPauseLimit)
        } else {
            noWindowUntil = nil
            noWindowWait = Self.noWindowPause
        }
        return buttons
    }

    /// Starts learning again once the button has been missing for long from
    /// a page that has loaded.
    private func noteMissing(buttons: [PageButton]?, at now: Date) {
        guard learner == nil, let buttons, buttons.count >= Self.loadedPageButtons else {
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

    // MARK: - Learning

    private func learn(buttons: [PageButton]?, pid: pid_t, now: Date) -> PlayerState {
        guard var learner else { return .unknown }
        let sound = page.isPlayingSound(pid: pid)
        learner.observe(buttons, soundIsOn: sound, at: now)
        let candidates = learner.candidates.compactMap { candidate in page.place(of: candidate.handle).map { (candidate, $0) } }
        if let (learned, handle) = PlayPauseLearner.recipe(from: candidates) {
            let merged = recipe?.merging(learned) ?? learned
            recipe = merged
            button = handle
            missingSince = nil
            self.learner = nil
            store.save(merged, for: bundleID)
            logger.notice("Learned \(self.name, privacy: .public)'s Play/Pause button")
            status.send(.learned)
            if let found = page.button(handle) { return Self.state(of: found, recipe: merged) }
            return .unknown
        }
        self.learner = learner
        status.send(.learning(hasPlayed: learner.hasPlayed))
        guard buttons != nil else { return .stopped }
        return sound ? .playing : .paused
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

    /// Tells the listeners, if it changed.
    func send(_ status: LearningStatus) {
        let listeners = state.withLock { state -> [AsyncStream<LearningStatus>.Continuation] in
            guard state.current != status else { return [] }
            state.current = status
            return Array(state.listeners.values)
        }
        listeners.forEach { $0.yield(status) }
    }

    /// The status now, then each change.
    func updates() -> AsyncStream<LearningStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: LearningStatus.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        let current = state.withLock { state in
            state.listeners[id] = continuation
            return state.current
        }
        continuation.yield(current)
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.listeners.removeValue(forKey: id) }
        }
        return stream
    }
}
