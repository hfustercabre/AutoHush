import AutoHushKit
import SpotifySupport

/// The music players AutoHush ships with. Each lives in its own
/// `<App>Support` target; adding one means adding it here.
package enum SupportedPlayers {
    /// The player AutoHush controls.
    package static func makeDefault() -> any MusicPlayer { SpotifyPlayer() }

    /// Bundle IDs of every supported player: their own audio is the music
    /// being protected, never a reason to pause.
    package static let bundleIDs: Set<String> = [SpotifyPlayer.appBundleID]

    /// A supported player by bundle ID (e.g. for the measuring tool).
    package static func player(bundleID: String) -> (any MusicPlayer)? {
        bundleID == SpotifyPlayer.appBundleID ? SpotifyPlayer() : nil
    }
}
