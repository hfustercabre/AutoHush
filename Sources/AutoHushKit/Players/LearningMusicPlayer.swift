import Foundation

/// A player AutoHush can only control once it has learned how, by watching
/// the user play and pause it once (a web app: which of the page's buttons
/// plays and pauses it). Until then it reports what it can, but can't be
/// paused; it learns while its state is read.
package protocol LearningMusicPlayer: MusicPlayer {
    /// Where learning stands now.
    var learningStatus: LearningStatus { get }
    /// The status now, then every change.
    func learningUpdates() -> AsyncStream<LearningStatus>
    /// Learns it again from the user, who asked (it may have been learned
    /// wrong). What it learned is kept, and controls it, until the user says
    /// it plays (`markPlaying`, taken): it's forgotten only then
    /// (`.relearning` meanwhile). Never learned, learning starts over.
    func learnAgain() async
    /// The user left learning again before saying it plays (the learning
    /// window was closed): what it learned stays, as before.
    func keepLearned() async
    /// The user says the music itself plays now ("It's Playing"): it notes
    /// how the player looks, and waits to be told it's paused.
    func markPlaying() async -> LearningMark
    /// Right after `markPlaying` noted it: it pauses itself, without the
    /// user (the keyboard's Play/Pause key), learns what changed, and plays
    /// again. Unless it's `.paused`, the user pauses it, then says so.
    func pauseByItself() async -> SelfPause
    /// The user says they paused it ("It's Paused"): it learns what changed
    /// since it played.
    func markPaused() async -> LearningMark
    /// The pause didn't come within `LearningStatus.pauseWait`, or it plays
    /// no more when asked to try again: it waits to be told it plays again.
    /// `false` when it wasn't waiting for the pause any more (It's Paused
    /// came at the last moment).
    @discardableResult
    func restartLearning() async -> Bool
}

/// How far a `LearningMusicPlayer` has come.
package enum LearningStatus: Equatable, Sendable {
    /// It can be controlled.
    case learned
    /// It waits for the user to say it plays (`hasPlayed` once they have),
    /// then that they paused it: then it has learned.
    case learning(hasPlayed: Bool)
    /// Learned, and still controlled with it, while the user learns it again
    /// (they asked): it waits for them to say it plays, and forgets what it
    /// learned only then.
    case relearning

    /// It can be controlled with what it learned.
    package var isLearned: Bool {
        if case .learning = self { return false }
        return true
    }

    /// How long the user has to pause it and say so, once they said it
    /// plays; then it starts over.
    package static let pauseWait: TimeInterval = 60
}

/// What came of the user telling a learning player it plays, or was paused.
package enum LearningMark: Equatable, Sendable {
    /// Noted (it plays), or learned (it was paused).
    case noted
    /// It can't be heard: it isn't playing yet.
    case notHeard
    /// Nothing changed since it played: it isn't paused yet.
    case nothingChanged
    /// It played longer ago than `LearningStatus.pauseWait`: start over.
    case tooLate
    /// Its page can't be read (it isn't running, has no window, or its window
    /// shows no usable buttons, as one macOS restores at login can): it waits
    /// to be told it plays again, once the page can be read.
    case cantSeePage
    /// It isn't learning.
    case notLearning
}

/// How a learning player's own pause went (`pauseByItself`).
package enum SelfPause: Equatable, Sendable {
    /// It paused, learned what changed, and plays again.
    case paused
    /// The pause didn't take: nothing changed (what was pressed is undone).
    case didntTake
    /// Another app is Now Playing, so the Play/Pause key would reach that
    /// one: nothing was pressed.
    case keyGoesElsewhere
}
