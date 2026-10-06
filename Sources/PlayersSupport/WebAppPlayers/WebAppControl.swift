import Foundation
import OSLog
import os
import AutoHushKit

/// Everything `SafariWebAppPlayer` does with the web app's page, run on the
/// player's own queue, one call at a time (Accessibility calls block).
///
/// Once it knows the button (`PlayPauseRecipe`), the music's state is what
/// the button says: a cheap read of one element. After a reload every
/// element is new, so the button is looked for again. While it doesn't know
/// the button, it learns it (`PlayPauseLearner`), and reports the music as
/// playing while the app's sound is on.
///
/// When the page shows but the button can't be found for a minute (the site
/// changed), it learns again, keeping what it knew: if the button turns up
/// again, it stops learning.
///
/// A site may refuse to pause: it disables its button during an ad, or a
/// press doesn't take. Only then is the web app muted instead (`AudioMuting`)
/// and reported as paused, until it's played again or monitoring stops.
final class WebAppControl: @unchecked Sendable {
    /// After a look finds no window, the next one waits this long: looking
    /// for windows on other Spaces tries a thousand elements.
    static let noWindowPause: TimeInterval = 5
    /// The button missing this long from a page that shows starts learning.
    static let missingBeforeLearning: TimeInterval = 60
    /// A page with fewer buttons is still loading (or asks to log in).
    static let loadedPageButtons = 10
    /// After a press, how long the button gets to change its words.
    static let pressConfirmation: TimeInterval = 2
    static let pressCheckInterval: TimeInterval = 0.1

    private let name: String
    private let bundleID: String
    private let page: any WebPage
    private let store: any PlayPauseRecipeStore
    private let clock: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) -> Void
    private let status: LearningStatusBroadcast
    private let muter: any AudioMuting
    private let logger = Logger(category: "WebAppPlayer")

    private var recipe: PlayPauseRecipe?
    /// The learned button, as last found.
    private var button: ButtonHandle?
    /// Learning, when there's no recipe or the button went missing.
    private var learner: PlayPauseLearner?
    /// Since when the page shows without the learned button.
    private var missingSince: Date?
    private var noWindowUntil: Date?

    /// Why the web app was muted instead of paused.
    private enum MuteReason {
        /// Its button was disabled (an ad): nothing was pressed.
        case buttonDisabled
        /// A press didn't take in time; it may still pause the page later.
        case pressIgnored
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
        clock: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (TimeInterval) -> Void
    ) {
        self.name = name
        self.bundleID = bundleID
        self.page = page
        self.store = store
        self.status = status
        self.muter = muter
        self.clock = clock
        self.sleep = sleep
        recipe = store.recipe(for: bundleID)
        if recipe == nil { learner = PlayPauseLearner() }
        status.send(recipe == nil ? .learning(hasPlayed: false) : .learned)
    }

    /// The music's state in the app running as `pid`. Learns meanwhile.
    func state(pid: pid_t) -> PlayerState {
        if let muted {
            if muted.pid == pid { return .paused } // muted in place of a pause
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
        guard learner == nil, let recipe, let button else {
            throw MusicPlayerError.playerCommandFailed("AutoHush hasn't learned \(name)'s Play/Pause button yet")
        }
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
        let deadline = clock().addingTimeInterval(Self.pressConfirmation)
        repeat {
            if let now = page.button(button), let shown = recipe.state(of: now), shown != state { return }
            sleep(Self.pressCheckInterval)
        } while clock() < deadline
        logger.error("\(self.name, privacy: .public)'s Play/Pause didn't change after a press")
        if state == .playing, mute(pid: pid, reason: .pressIgnored) { return }
        throw MusicPlayerError.playerCommandFailed("\(name) didn't respond to its Play/Pause button")
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
        guard muter.mute(appPID: pid) else { return false }
        muted = (pid, reason)
        logger.notice("\(self.name, privacy: .public) refused to pause: muted instead")
        return true
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

    private func lookup(_ recipe: PlayPauseRecipe, pid: pid_t, now: Date) -> Lookup {
        if let button, let found = page.button(button), recipe.state(of: found) != nil {
            return .found(found)
        }
        button = nil
        guard let buttons = look(pid: pid, now: now) else { return .noWindow }
        guard let found = recipe.find(in: buttons, place: page.place(of:)) else { return .missing(buttons: buttons) }
        button = found.handle
        return .found(found)
    }

    /// The page's buttons; `nil` while the app has no window, and for a
    /// while after a look found none.
    private func look(pid: pid_t, now: Date) -> [PageButton]? {
        if let noWindowUntil, now < noWindowUntil { return nil }
        let buttons = page.buttons(pid: pid)
        noWindowUntil = buttons == nil ? now.addingTimeInterval(Self.noWindowPause) : nil
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
