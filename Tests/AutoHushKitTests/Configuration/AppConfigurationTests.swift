import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("AppConfiguration")
struct AppConfigurationTests {

    // MARK: - isMediaSource

    @Test("rejects the music player's own bundle ID")
    func rejectsMusicPlayer() {
        #expect(AppConfiguration.testing.isMediaSource(TestPlayer.bundleID) == false)
        // The engine itself knows no player: the app tells it which ones it supports.
        #expect(AppConfiguration().isMediaSource(TestPlayer.bundleID) == true)
    }

    @Test("rejects system audio processes and an empty ID", arguments: [
        "",
        "com.apple.coreaudiod",
        "com.apple.audio.SandboxHelper",
        "com.apple.audio.UISoundsServer",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "systemsoundserverd",              // plays notification and alert sounds for every app
        "com.apple.audio.SomeNewDaemon",   // anything with the com.apple.audio. prefix
        "com.apple.audio.UnknownHelper",
    ])
    func rejects(bundleID: String) {
        #expect(AppConfiguration().isMediaSource(bundleID) == false)
    }

    @Test("accepts media apps, including ones it knows nothing about", arguments: [
        "org.videolan.vlc",
        "com.colliderli.iina",
        "com.google.Chrome",
        "com.google.Chrome.helper",
        "org.mozilla.firefox",
        "com.apple.Safari",
        "com.apple.QuickTimePlayerX",
        "com.apple.music",
        "com.example.randomplayer",
        "io.some.mediaplayer",
    ])
    func accepts(bundleID: String) {
        #expect(AppConfiguration().isMediaSource(bundleID) == true)
    }

    // MARK: - Defaults

    @Test("the chosen player's helpers count as the player, look-alikes don't")
    func playerHelpers() {
        var configuration = AppConfiguration()
        configuration.musicPlayerBundleID = "com.example.jukebox"
        #expect(configuration.isMusicPlayer("com.example.jukebox"))
        #expect(configuration.isMusicPlayer("com.example.jukebox.helper"))
        #expect(!configuration.isMusicPlayer("com.example.jukeboxes"))
        #expect(!configuration.isMediaSource("com.example.jukebox.helper"))
        configuration.musicPlayerBundleID = nil
        #expect(!configuration.isMusicPlayer("com.example.jukebox"))
    }

    @Test("the defaults come from the timing settings' defaults")
    func defaults() {
        let configuration = AppConfiguration()
        #expect(configuration.sourceStartConfirmation == 0.5)
        #expect(configuration.sourceStopGrace == 2)
        #expect(TimingSettings.defaults.startConfirmation == 0.5)
    }

    @Test("in AntiDot mode, sound without video must last at least 3 s, or the user's longer choice")
    func startWithoutVideo() {
        #expect(AppConfiguration().startConfirmationWithoutVideo == 3)
        #expect(AppConfiguration(timings: TimingSettings(startConfirmation: 4)).startConfirmationWithoutVideo == 4)
    }
}
