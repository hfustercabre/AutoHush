import AutoHushKit
import SpotifySupport

/// The music players AutoHush ships with. Each lives in its own
/// `<App>Support` target; adding one means adding it to `catalog`.
package enum SupportedPlayers {
    /// Every supported player, in the order they're offered. Spotify was the
    /// only player before the choice, so people updating keep it.
    package static let catalog = MusicPlayerCatalog(
        players: [SpotifyPlayer()],
        formerDefault: SpotifyPlayer.appBundleID
    )
}
