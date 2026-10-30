import AutoHushKit

/// The music player in engine tests. The engine knows no player by name, so
/// tests tell it which app's audio is the music, like the app does.
package enum TestPlayer {
    package static let bundleID = "com.example.jukebox"
}

extension AppConfiguration {
    /// The default configuration, with `TestPlayer` as the chosen player.
    package static var testing: AppConfiguration {
        var configuration = AppConfiguration(timings: .defaults)
        configuration.musicPlayerBundleID = TestPlayer.bundleID
        return configuration
    }
}
