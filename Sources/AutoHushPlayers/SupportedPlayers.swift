import AutoHushKit
import ScriptablePlayers
import MenuPlayers
import SpotifySupport
import AppleMusicSupport
import TidalSupport
import PodcastsSupport
import VLCSupport

/// The music players AutoHush ships with. Each lives in its own
/// `<App>Support` target; adding one means adding it to `catalog`.
package enum SupportedPlayers {
    /// Every supported player, in the order they're offered. Spotify was the
    /// only player before the choice, so people updating keep it.
    package static let catalog = MusicPlayerCatalog(
        players: [
            ScriptablePlayer(profile: .spotify),
            ScriptablePlayer(profile: .appleMusic),
            MenuPlayer(profile: .tidal),
            MenuPlayer(profile: .applePodcasts),
            VLCPlayer(),
        ],
        formerDefault: ScriptablePlayerProfile.spotify.bundleID
    )
}
