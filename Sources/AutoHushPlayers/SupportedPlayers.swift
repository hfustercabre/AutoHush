import AutoHushKit
import SpotifySupport

/// The music players AutoHush ships with. Each lives in its own
/// `<App>Support` target; adding one means adding it to `all`.
package enum SupportedPlayers {
    /// Every supported player by bundle ID. The first is the one AutoHush controls.
    private static let all: [(bundleID: String, make: @Sendable () -> any MusicPlayer)] = [
        (SpotifyPlayer.appBundleID, { SpotifyPlayer() }),
    ]

    /// The player AutoHush controls.
    package static func makeDefault() -> any MusicPlayer { all[0].make() }

    /// Bundle IDs of every supported player: their own audio is the music
    /// being protected, never a reason to pause.
    package static let bundleIDs = Set(all.map(\.bundleID))

    /// A supported player by bundle ID (e.g. for the measuring tool).
    package static func player(bundleID: String) -> (any MusicPlayer)? {
        all.first { $0.bundleID == bundleID }?.make()
    }
}
