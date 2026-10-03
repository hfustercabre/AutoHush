import Foundation

/// A music app AutoHush pauses while other apps play, and resumes afterwards.
///
/// Each supported app (Spotify today) implements this once; the rest of
/// AutoHush only talks to players through it.
protocol MusicPlayer: Sendable {
    /// The app's bundle identifier. Its own audio is the music being
    /// protected, so it never counts as another app playing.
    var bundleID: String { get }
    /// Name shown to the user, e.g. "Spotify".
    var name: String { get }

    /// Asks for (if needed) and checks permission to control the player.
    /// Throws an `AutoHushError` when the player can't be controlled.
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

    /// Reports the player's state changes (and its quitting) once started.
    @MainActor
    func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving
}

extension MusicPlayer {
    /// Until a player's curve is measured, its volume is taken as linear.
    var volumeCurve: VolumeCurve { .linear }
}

/// Watches a player's state; created by `MusicPlayer.makeStateObserver`.
@MainActor
protocol PlayerStateObserving: AnyObject {
    func start()
    func stop()
}

/// The players AutoHush supports.
enum SupportedPlayers {
    /// Bundle IDs of every supported player: their audio is never a reason to pause.
    static let bundleIDs: Set<String> = [SpotifyPlayer.appBundleID]
}
