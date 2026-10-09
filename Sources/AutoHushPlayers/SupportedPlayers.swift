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
        // Shown in Add a Web App's address field and its "not a web address" note.
        exampleWebAddress: "music.youtube.com",
        found: { webApps.current() },
        suggested: { webApps.suggestions() }
    )

    /// The music services' web players AutoHush has been tested with (live,
    /// 2026-10-06), the most used first: Spotify, YouTube Music (125 million
    /// subscribers), Amazon Music, then Deezer (about 10 million). Their web
    /// apps are offered first, and suggested until added; any other web app
    /// is offered after them, marked untested.
    package static let testedWebApps: [TestedWebApp] = [
        TestedWebApp(name: "Spotify", address: "open.spotify.com"),
        TestedWebApp(name: "YouTube Music", address: "music.youtube.com"),
        TestedWebApp(name: "Amazon Music", address: amazonMusicSite(region: Locale.current.region?.identifier),
                     otherHosts: ["music.amazon.com"] + amazonMusicSites.values),
        TestedWebApp(name: "Deezer", address: "deezer.com"),
    ]

    /// The Safari web apps in the Applications folders, looked for once for
    /// the players, the suggestions and Add a Web App.
    private static let webAppFinder = SafariWebAppFinder()

    /// Every Safari web app (YouTube Music, Amazon Music, Spotify's web
    /// player…) can be chosen: AutoHush learns its Play/Pause button.
    private static let webApps = SafariWebAppPlayers(finder: webAppFinder, tested: testedWebApps)

    /// Amazon Music's site for each country that has its own; the others
    /// use music.amazon.com. A sign-in on another country's site doesn't
    /// carry over, so the web app opens the Mac's own.
    package static let amazonMusicSites: [String: String] = [
        "GB": "music.amazon.co.uk", "DE": "music.amazon.de", "AT": "music.amazon.de",
        "FR": "music.amazon.fr", "IT": "music.amazon.it", "ES": "music.amazon.es",
        "JP": "music.amazon.co.jp", "CA": "music.amazon.ca", "BR": "music.amazon.com.br",
        "MX": "music.amazon.com.mx", "IN": "music.amazon.in", "AU": "music.amazon.com.au",
    ]

    package static func amazonMusicSite(region: String?) -> String {
        region.flatMap { amazonMusicSites[$0] } ?? "music.amazon.com"
    }

    /// Makes a Safari web app from an address the user typed.
    package static let webAppMaker: any WebAppMaking = SafariWebAppMaker(
        webApps: { webAppFinder.webApps(maxAge: 0) },
        sameSite: { TestedWebApp.sameSite($0, $1, tested: testedWebApps) }
    )

    /// The app a process runs as when its program doesn't say: a Safari web
    /// app (for `ProcessAudioSourceIdentifier`).
    package static func hostedApp(pid: pid_t) -> AudioSource? {
        SafariWebApp.source(forProcess: pid)
    }
}
