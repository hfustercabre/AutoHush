import Testing
@testable import AutoHush

@Suite("AppConfiguration")
struct AppConfigurationTests {

    // MARK: - isMediaSource: exclusions

    @Test("rejects Spotify's own bundle ID")
    func rejectsSpotify() {
        #expect(AppConfiguration().isMediaSource("com.spotify.client") == false)
    }

    @Test("rejects empty string")
    func rejectsEmptyString() {
        #expect(AppConfiguration().isMediaSource("") == false)
    }

    @Test("rejects known system audio daemons")
    func rejectsSystemDaemons() {
        let config = AppConfiguration()
        let daemons = [
            "com.apple.coreaudiod",
            "com.apple.audio.SandboxHelper",
            "com.apple.audio.UISoundsServer",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
        ]
        for daemon in daemons {
            #expect(config.isMediaSource(daemon) == false, "Expected \(daemon) to be excluded")
        }
    }

    @Test("rejects any bundle ID with the com.apple.audio. prefix")
    func rejectsCoreAudioPrefix() {
        let config = AppConfiguration()
        #expect(config.isMediaSource("com.apple.audio.SomeNewDaemon") == false)
        #expect(config.isMediaSource("com.apple.audio.UnknownHelper") == false)
    }

    // MARK: - isMediaSource: allowances

    @Test("accepts VLC")
    func acceptsVLC() {
        #expect(AppConfiguration().isMediaSource("org.videolan.vlc") == true)
    }

    @Test("accepts IINA")
    func acceptsIINA() {
        #expect(AppConfiguration().isMediaSource("com.colliderli.iina") == true)
    }

    @Test("accepts Google Chrome and its renderer helper")
    func acceptsChrome() {
        let config = AppConfiguration()
        #expect(config.isMediaSource("com.google.Chrome") == true)
        #expect(config.isMediaSource("com.google.Chrome.helper") == true)
    }

    @Test("accepts Firefox")
    func acceptsFirefox() {
        #expect(AppConfiguration().isMediaSource("org.mozilla.firefox") == true)
    }

    @Test("accepts Safari")
    func acceptsSafari() {
        #expect(AppConfiguration().isMediaSource("com.apple.Safari") == true)
    }

    @Test("accepts QuickTime Player")
    func acceptsQuickTimePlayer() {
        #expect(AppConfiguration().isMediaSource("com.apple.QuickTimePlayerX") == true)
    }

    @Test("accepts Apple Music")
    func acceptsAppleMusic() {
        #expect(AppConfiguration().isMediaSource("com.apple.music") == true)
    }

    @Test("accepts arbitrary unknown apps")
    func acceptsUnknownApps() {
        #expect(AppConfiguration().isMediaSource("com.example.randomplayer") == true)
        #expect(AppConfiguration().isMediaSource("io.some.mediaplayer") == true)
    }

    // MARK: - Default values

    @Test("default debounce is 0.2 seconds")
    func defaultDebounce() {
        #expect(AppConfiguration().debounceSeconds == 0.2)
    }

    @Test("system sounds played by systemsoundserverd never count")
    func excludesSystemSoundServer() {
        #expect(AppConfiguration().isMediaSource("systemsoundserverd") == false)
    }

    @Test("default start confirmation is half a second")
    func defaultStartConfirmation() {
        #expect(AppConfiguration().sourceStartConfirmation == 0.5)
        #expect(TimingSettings.defaults.startConfirmation == 0.5)
    }
}
