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
    /// Every supported player, the most used first (2026): Spotify (777
    /// million monthly users), Apple Music (about 100 million subscribers),
    /// VLC (over 6 billion downloads), Apple Podcasts (a tenth of podcast
    /// listeners), then TIDAL (a few million). Installed players are offered
    /// before the others, each group in this order. Spotify was the only
    /// player before the choice, so people updating keep it.
    package static let catalog = MusicPlayerCatalog(
        players: [
            ScriptablePlayer(profile: .spotify),
            ScriptablePlayer(profile: .appleMusic),
            VLCPlayer(),
            MenuPlayer(profile: .applePodcasts),
            MenuPlayer(profile: .tidal),
        ],
        formerDefault: ScriptablePlayerProfile.spotify.bundleID
    )
}
