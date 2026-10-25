import Foundation

/// A music app AutoHush pauses while other apps play, and resumes afterwards.
///
/// Each supported app implements this once, in its own `<App>Support`
/// target; the rest of AutoHush only talks to players through it, and
/// controls the one the user chose.
package protocol MusicPlayer: Sendable {
    /// The app's bundle identifier. While the player is the chosen one, its
    /// own audio is the music being protected, so it never counts as another
    /// app playing.
    var bundleID: String { get }
    /// Name shown to the user, the app's own.
    var name: String { get }
    /// Drawn in place of the app's icon while it isn't installed; `nil` for
    /// the generic app icon.
    var iconPlaceholder: PlayerIconPlaceholder? { get }
    /// The permission AutoHush needs to control it, for Diagnostics.
    var controlPermission: Permission { get }
    /// What kind of app it is; players are offered grouped by kind.
    var kind: MusicPlayerKind { get }
    /// Where it's installed, when the player knows (a web app, found in the
    /// Applications folders); `nil` to ask macOS by its bundle ID, which can
    /// take a moment to learn of a new app.
    var installedURL: URL? { get }
    /// Offered without AutoHush having been tried with it (the web app of a
    /// site nobody has tested), and marked so.
    var isUntested: Bool { get }
    /// For a player whose state is told apart by its own words for Play and
    /// Pause, read from its app (one controlled through its menu): whether
    /// they could be read; `nil` for any other player. Diagnostics shows it.
    var ownWordsRead: Bool? { get }

    /// Asks for (if needed) and checks permission to control the player.
    /// Throws a `MusicPlayerError` when the player can't be controlled.
    func verifyControlAccess() async throws
    /// The player's live state; `.unknown` when it does not answer.
    func playerState() async -> PlayerState
    func pause() async throws
    func play() async throws
    /// Whether its `pause()` and `play()` check by themselves that they took
    /// (a web app's, which mutes a page that refuses to pause); any other's
    /// presses are checked by `PressCheck`.
    var checksItsPresses: Bool { get }

    /// Whether its state comes from the player itself (its script, its page,
    /// a Now Playing report), not only from its open output: one that says
    /// nothing (a player's trailers, reported as Unknown) isn't playing
    /// silently, just not known to play.
    func statesItself() async -> Bool

    /// Its pause by a way that shows nothing on screen: pressed again while
    /// it's muted in place of a pause, every couple of seconds (the user,
    /// 2026-10-25: never the Now Playing panel). Its plain pause by default.
    func pauseQuietly() async throws

    /// The player's own volume, 0–100, or `nil` when it can't be read.
    /// Fades need it; players without one pause and play without fading.
    func volume() async -> Int?
    func setVolume(_ volume: Int) async throws
    /// How the volume number maps to loudness, so fades sound even.
    var volumeCurve: VolumeCurve { get }
    /// Whether AutoHush can change the player's volume to fade it. One that
    /// can't pauses and plays at once, and Settings says so.
    var canFade: Bool { get }

    /// Reports the player's state changes (and its quitting) once started.
    @MainActor
    func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving
    /// It's no longer the player (AutoHush quits, or another player is
    /// chosen and AutoHush holds no pause in it): whatever it turned on in
    /// its app to control it (an Electron or Chromium app's switch for
    /// assistive tools) goes back off, and a mute it holds is lifted, when
    /// `releasesOnQuit`. It can be called at any time; chosen again, the
    /// player turns on what it needs again.
    func release() async
    /// Whether `release` has anything to undo.
    var releasesOnQuit: Bool { get }
    /// It's never paused, but muted while other apps play (an app added with
    /// Add an App that no way pauses): the menu says "Muted", with Unmute.
    var pausesByMuting: Bool { get }
    /// Only its sound level tells how it is (muted only, or controlled
    /// through a Now Playing row that doesn't follow it): not in AntiDot
    /// mode, which measures none.
    var needsAudioLevels: Bool { get }
    /// It runs, but was opened without what it needs to be controlled
    /// wherever its window is (an Electron app's launch option, without
    /// which its page takes no presses while covered or on another desktop):
    /// `reopen()` fixes that.
    func needsReopen() async -> Bool
    /// Quits it (never by force) and opens it again, in the background, as
    /// it needs to be; whether it did.
    func reopen() async -> Bool
    /// How late its observer can report a change, in seconds: 0 for a player
    /// that announces each one, `PolledStateObserver.reportDelay` for one
    /// whose state is read now and then. No default: a wrong 0 would make
    /// late reports look prompt.
    var stateReportDelay: TimeInterval { get }
}

extension MusicPlayer {
    /// Until a player's curve is measured, its volume is taken as linear.
    package var volumeCurve: VolumeCurve { .linear }
    package var canFade: Bool { true }
    package var iconPlaceholder: PlayerIconPlaceholder? { nil }
    package var kind: MusicPlayerKind { .app }
    package var installedURL: URL? { nil }
    package var isUntested: Bool { false }
    package var ownWordsRead: Bool? { nil }
    package var checksItsPresses: Bool { false }
    package func statesItself() async -> Bool { true }
    package func pauseQuietly() async throws { try await pause() }
    package func release() async {}
    package var releasesOnQuit: Bool { false }
    package var pausesByMuting: Bool { false }
    package var needsAudioLevels: Bool { false }
    package func needsReopen() async -> Bool { false }
    package func reopen() async -> Bool { false }
    /// Most players are scripted with Apple events.
    package var controlPermission: Permission { .automation(player: name) }
}

/// A player whose volume can't be read or set (one controlled through its
/// menu, its page or the Now Playing panel): it pauses and plays without
/// fading. Opting in gives it those answers.
package protocol FadelessMusicPlayer: MusicPlayer {}

extension FadelessMusicPlayer {
    package var canFade: Bool { false }
    package func volume() async -> Int? { nil }
    package func setVolume(_ volume: Int) async throws {}
}

/// A player that announces nothing, so its state is read about once a
/// second (`PolledStateObserver`). Opting in gives it that observer, and
/// says how late it may report a change (`stateReportDelay`); one with an
/// observer of its own keeps it.
package protocol PolledMusicPlayer: MusicPlayer {}

extension PolledMusicPlayer {
    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        PolledStateObserver(read: { [self] in await self.playerState() }, onChange: onChange)
    }

    package var stateReportDelay: TimeInterval { PolledStateObserver.reportDelay }
}

/// What kind of app a player is.
package enum MusicPlayerKind: Sendable {
    /// An app of its own.
    case app
    /// A website added to the Dock from Safari (File → Add to Dock).
    case safariWebApp
    /// An app AutoHush has no support of its own for, added through a check
    /// (Add an App…): controlled the ways the check found to work.
    case checkedApp
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

/// A player that mutes itself when it refuses to pause (see `AudioMuting`),
/// through Core Audio's process taps on its own sound, which may also tell
/// whether it can be heard.
package protocol MutingMusicPlayer: MusicPlayer {
    /// Whether it may tap its sound: not in AntiDot mode, which promises no
    /// audio taps. Without taps it doesn't mute.
    func allowTaps(_ allowed: Bool)
    /// For a player that says it isn't playing while it can be heard (a web
    /// app during an ad its site won't pause): mutes it until it's played
    /// again, as for a refused pause. `false` when it's silent, or muting
    /// isn't possible or allowed.
    func muteIfPlayingAnyway() async -> Bool
    /// AutoHush no longer holds the pause a mute stands in for (the Mac
    /// slept): the player is paused for real as soon as it can be, and the
    /// mute lifted then, or once it's silent. It isn't played again.
    func forgetPause() async
    /// Lifts a mute `muteIfPlayingAnyway` left, without playing anything:
    /// once AutoHush no longer watches it (its monitoring stopped).
    func releaseMute() async
    /// Whether its pause is a mute of its own now (a web page during an ad
    /// its site won't pause): AutoHush leaves it to that mute.
    func isMutedForPause() async -> Bool
}

extension MutingMusicPlayer {
    package func isMutedForPause() async -> Bool { false }
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

/// Watches a player's state; created by `MusicPlayer.makeStateObserver`.
@MainActor
package protocol PlayerStateObserving: AnyObject {
    func start()
    func stop()
}
