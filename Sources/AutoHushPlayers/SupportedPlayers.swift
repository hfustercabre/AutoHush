import Foundation
import AutoHushKit
import ScriptablePlayers
import MenuPlayers
import WebAppPlayers
import SpotifySupport
import AppleMusicSupport
import TidalSupport
import PodcastsSupport
import VLCSupport

/// The music players AutoHush ships with, plus the Safari web apps on this
/// Mac. Each app lives in its own `<App>Support` target; adding one means
/// adding it to `catalog`.
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
        formerDefault: ScriptablePlayerProfile.spotify.bundleID,
        found: { webApps.current() }
    )

    /// Every Safari web app (YouTube Music, Amazon Music, Spotify's web
    /// player…) can be chosen: AutoHush learns its Play/Pause button.
    private static let webApps = SafariWebAppPlayers()

    /// The app a process runs as when its program doesn't say: a Safari web
    /// app (for `ProcessAudioSourceIdentifier`).
    package static func hostedApp(pid: pid_t) -> AudioSource? {
        SafariWebApp.source(forProcess: pid)
    }
}
