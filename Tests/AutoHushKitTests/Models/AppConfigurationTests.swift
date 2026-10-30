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
        "com.apple.systemsound",
        "com.apple.springboard",
        "com.apple.PowerChime",            // the chime as power is plugged in
        "com.apple.mail",                  // Mail's own sounds
        "com.apple.CoreAudio.SomeHelper",  // anything with the com.apple.CoreAudio prefix
    ])
    func rejects(bundleID: String) {
        #expect(AppConfiguration().isMediaSource(bundleID) == false)
    }

    @Test("accepts media apps, including ones it knows nothing about", arguments: [
        "org.example.viewer",
        "com.example.videoplayer",
        "com.google.Chrome",
        "com.google.Chrome.helper",
        "org.mozilla.firefox",
        "com.apple.Safari",
        "com.example.movies",
        "com.example.library",
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
    }

    @Test("in AntiDot mode, sound without video must last at least 3 s, or the user's longer choice")
    func startWithoutVideo() {
        #expect(AppConfiguration().startConfirmationWithoutVideo == 3)
        #expect(AppConfiguration(timings: TimingSettings(startConfirmation: 4)).startConfirmationWithoutVideo == 4)
    }

    @Test("with open streams only, any app's sound must last at least 2 s, or the user's longer choice")
    func startWithOpenStreams() {
        #expect(AppConfiguration().startConfirmationWithOpenStreams == 2)
        #expect(AppConfiguration(timings: TimingSettings(startConfirmation: 4)).startConfirmationWithOpenStreams == 4)
    }
}
