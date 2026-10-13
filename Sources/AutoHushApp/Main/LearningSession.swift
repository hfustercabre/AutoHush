import Foundation
import OSLog
import AutoHushKit

/// Where the pause stands while the user teaches AutoHush a web app's
/// controls, for the windows that show the steps.
struct LearningPause: Equatable {
    /// Once the user said it plays and is to pause it: when learning starts
    /// over without the pause.
    var deadline: Date?
    /// Why the user's last click didn't move it on.
    var note: LearningNote?
    /// Once the user said it plays: AutoHush pauses it itself, to learn which
    /// button changes, or, when it couldn't, the user does.
    var mode = LearningPauseMode.automatic
}

/// Learning the chosen web app's controls with the user (see GLOSSARY.md).
/// It follows the player's learning status, takes the user's steps (It's
/// Playing, Try Again, Pause It Manually, It's Paused), and counts down the
/// minute the user has to pause it, with a note when a step can't be taken.
/// The windows that show the steps are AppDelegate's; they show its state.
@MainActor
final class LearningSession {
    /// What the windows show of it.
    struct State: Equatable {
        /// How far learning has come; `nil` for a player that learns nothing.
        var status: LearningStatus?
        var pause = LearningPause()
    }

    private(set) var state = State() {
        didSet { if state != oldValue { didChange(state) } }
    }
    /// Called each time `state` changes.
    var didChange: @MainActor (State) -> Void = { _ in }

    /// The chosen player, while it's one that learns.
    private var learner: (any LearningMusicPlayer)?
    /// Follows how learning the chosen player goes.
    private var watch: Task<Void, Never>?
    /// Runs while the user has said the player plays: once `pauseWait` is
    /// over, learning starts over.
    private(set) var countdown: Task<Void, Never>?
    /// How long the user has to pause the player and say so
    /// (`LearningStatus.pauseWait`).
    private let pauseWait: Duration
    /// How `countdown` waits (tests end the wait themselves).
    private let sleep: @Sendable (Duration) async -> Void
    private let logger = Logger(category: "LearningSession")

    init(pauseWait: Duration = .seconds(LearningStatus.pauseWait),
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.pauseWait = pauseWait
        self.sleep = sleep
    }

    // MARK: - What the app tells it

    /// `player` is the chosen one now: its learning is followed as it goes,
    /// and nothing the last one was told carries over. A player that learns
    /// nothing (or none) leaves nothing to learn.
    func follow(_ player: (any MusicPlayer)?) {
        watch?.cancel()
        watch = nil
        countdown?.cancel()
        countdown = nil
        setPause(deadline: nil, note: nil, mode: .automatic)
        learner = player as? any LearningMusicPlayer
        guard let learner else {
            show(nil)
            return
        }
        show(learner.learningStatus)
        watch = Task { [weak self] in
            for await learning in learner.learningUpdates() {
                guard !Task.isCancelled else { return }
                self?.show(learning)
            }
        }
    }

    /// Learns the chosen player's controls afresh, as the user asked: once
    /// learned (they may have been learned wrong), or before (the learning
    /// window was closed halfway). What the player learned stays until the
    /// user says it plays there; closing the window before that keeps it
    /// (`windowClosed`). `false` when there's nothing to learn, or another
    /// player was chosen meanwhile.
    func learnAgain() async -> Bool {
        guard let learner else { return false }
        logger.notice("Learning \(learner.name, privacy: .public)'s controls again, as asked")
        countdown?.cancel()
        countdown = nil
        setPause(deadline: nil, note: nil, mode: .automatic)
        await learner.learnAgain()
        return isLearning(learner)
    }

    /// The user's clicks while AutoHush learns the chosen player: It's
    /// Playing, then, if AutoHush couldn't pause it itself, Try Again or
    /// Pause It Manually, and It's Paused. A click that can't be taken
    /// leaves a note under its step saying why.
    func step(_ button: StepButton) {
        guard let learner else { return }
        switch button {
        case .itsPlaying, .tryAgain: pauseByItself(learner)
        case .pauseManually: pauseByHand(learner)
        case .itsPaused: markPaused(learner)
        case .addToDock: break
        }
    }

    /// The learning window closed (Later, its close button, or learned):
    /// learning again, before the user said it plays, what the player
    /// learned stays. The player knows whether it was learning again: its
    /// status may say it learns meanwhile (its button went missing).
    func windowClosed() {
        guard let learner else { return }
        Task { await learner.keepLearned() }
    }

    // MARK: - The steps

    /// Whether `learner` is still the chosen player: an answer about another
    /// one changes nothing.
    private func isLearning(_ learner: any LearningMusicPlayer) -> Bool {
        self.learner?.bundleID == learner.bundleID
    }

    /// It plays (It's Playing, or Try Again): a fresh look at its page, then
    /// AutoHush pauses it itself and learns. When that doesn't take, its
    /// step is marked failed, offering Try Again and Pause It Manually; when
    /// another app would get the Play/Pause key, the user pauses it at once,
    /// as with Pause It Manually.
    private func pauseByItself(_ learner: any LearningMusicPlayer) {
        setPause(deadline: nil, note: nil, mode: .trying)
        Task { [weak self] in
            let mark = await learner.markPlaying()
            guard let self, self.isLearning(learner) else { return }
            guard mark == .noted else { return await self.backToPlaying(learner, after: mark) }
            let pause = await learner.pauseByItself()
            guard self.isLearning(learner), learner.learningStatus == .learning(hasPlayed: true) else { return }
            switch pause {
            case .paused:
                break
            case .didntTake:
                self.setPause(deadline: nil, note: nil, mode: .failed)
            case .keyGoesElsewhere:
                self.setPause(deadline: nil, note: nil, mode: .keyElsewhere)
                self.startCountdown()
            }
        }
    }

    /// Pause It Manually: a fresh look at its page while it plays, then the
    /// user has `pauseWait` to pause it and say so (It's Paused).
    private func pauseByHand(_ learner: any LearningMusicPlayer) {
        Task { [weak self] in
            let mark = await learner.markPlaying()
            guard let self, self.isLearning(learner) else { return }
            guard mark == .noted else { return await self.backToPlaying(learner, after: mark) }
            self.setPause(deadline: nil, note: nil, mode: .byHand)
            self.startCountdown()
        }
    }

    /// It's Paused: learned, or a note under the step saying why not.
    private func markPaused(_ learner: any LearningMusicPlayer) {
        Task { [weak self] in
            let mark = await learner.markPaused()
            guard let self, self.isLearning(learner) else { return }
            switch mark {
            case .nothingChanged: self.setPause(deadline: self.state.pause.deadline, note: .nothingChanged)
            case .tooLate:        self.setPause(deadline: nil, note: .timedOut, mode: .automatic)
            case .cantSeePage:    self.setPause(deadline: nil, note: .cantSeePage, mode: .automatic)
            case .noted, .notLearning, .notHeard: break
            }
        }
    }

    /// The look while it plays couldn't be taken (it's silent, or its page
    /// can't be read): back to the first step, saying why.
    private func backToPlaying(_ learner: any LearningMusicPlayer, after mark: LearningMark) async {
        if learner.learningStatus == .learning(hasPlayed: true) { await learner.restartLearning() }
        guard isLearning(learner) else { return }
        let note: LearningNote? = switch mark {
        case .notHeard: .notHeard
        case .cantSeePage: .cantSeePage
        default: nil
        }
        setPause(deadline: nil, note: note, mode: .automatic)
    }

    /// The user has `pauseWait` to pause the player and say so; the steps
    /// count it down, then learning starts over, saying why.
    private func startCountdown() {
        countdown?.cancel()
        setPause(deadline: Date().addingTimeInterval(Double(pauseWait.components.seconds)), note: nil)
        let wait = pauseWait
        let sleep = sleep
        countdown = Task { [weak self] in
            await sleep(wait)
            guard !Task.isCancelled, let learner = self?.learner else { return }
            // It's Paused may have come at the last moment: learned, nothing to say.
            if await learner.restartLearning() { self?.setPause(deadline: nil, note: .timedOut, mode: .automatic) }
        }
    }

    // MARK: - Its state

    /// Learning as the player reports it. Once it plays, AutoHush pauses it,
    /// or the user does (their minute starts at Pause It Manually). Back at
    /// the first step, the note that says why stays (set by whatever sent it
    /// back); learned, the steps show how it was paused; with nothing to
    /// learn, nothing shows.
    private func show(_ status: LearningStatus?) {
        var next = state
        next.status = status
        if status != .learning(hasPlayed: true) {
            countdown?.cancel()
            countdown = nil
            next.pause.deadline = nil
            switch status {
            case .learning?, .relearning?:
                next.pause.mode = .automatic
            case .learned?:
                next.pause.note = nil
                if next.pause.mode == .failed { next.pause.mode = .automatic }
            case nil:
                next.pause = LearningPause()
            }
        }
        state = next
    }

    /// The countdown's end, the note, and how the pause goes (`mode`; `nil`
    /// keeps it).
    private func setPause(deadline: Date?, note: LearningNote?, mode: LearningPauseMode? = nil) {
        var pause = state.pause
        pause.deadline = deadline
        pause.note = note
        if let mode { pause.mode = mode }
        state.pause = pause
    }
}
