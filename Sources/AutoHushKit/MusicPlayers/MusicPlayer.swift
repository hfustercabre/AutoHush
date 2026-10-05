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
    /// Name shown to the user, e.g. "Spotify".
    var name: String { get }

    /// Asks for (if needed) and checks permission to control the player.
    /// Throws a `MusicPlayerError` when the player can't be controlled.
    func verifyControlAccess() async throws
    /// The player's live state; `.unknown` when it does not answer.
    func playerState() async -> PlayerState
    func pause() async throws
    func play() async throws

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
}

extension MusicPlayer {
    /// Until a player's curve is measured, its volume is taken as linear.
    package var volumeCurve: VolumeCurve { .linear }
    package var canFade: Bool { true }
}

/// Watches a player's state; created by `MusicPlayer.makeStateObserver`.
@MainActor
package protocol PlayerStateObserving: AnyObject {
    func start()
    func stop()
}
