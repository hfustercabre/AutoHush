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

extension AppConfiguration {
    /// The engine's configuration for tests that drive the monitor:
    /// `TestPlayer` as the player, an app counting as playing at once, the
    /// music paused and played without fading, and the monitor looking only
    /// when the test changes the processes.
    package static var testTicksOnly: AppConfiguration {
        var timings = TimingSettings.defaults
        timings.startConfirmation = 0
        timings.fadesEnabled = false
        var configuration = AppConfiguration(timings: timings)
        configuration.musicPlayerBundleID = TestPlayer.bundleID
        configuration.activeSampleInterval = 3600 // ticks only when the test changes the processes
        configuration.idleSampleInterval = 3600
        return configuration
    }
}
