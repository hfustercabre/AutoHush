import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("Preferences")
@MainActor
struct PreferencesTests {
    /// Shared by several `Preferences` instances to check persistence.
    private final class Scratch {
        let defaults = InMemoryPreferenceStore()
    }

    @Test("auto-pause defaults to enabled without snooze")
    func defaults() {
        let scratch = Scratch()
        #expect(Preferences(store: scratch.defaults).autoPause == AutoPauseSetting())
        #expect(Preferences(store: scratch.defaults).ignoredApps.isEmpty)
    }

    @Test("auto-pause and its snooze persist")
    func autoPausePersists() {
        let scratch = Scratch()
        let until = Date(timeIntervalSinceReferenceDate: 1_000_000)
        Preferences(store: scratch.defaults).autoPause = AutoPauseSetting(isEnabled: true, snoozedUntil: until)
        #expect(Preferences(store: scratch.defaults).autoPause == AutoPauseSetting(isEnabled: true, snoozedUntil: until))

        Preferences(store: scratch.defaults).autoPause = AutoPauseSetting(isEnabled: false)
        #expect(Preferences(store: scratch.defaults).autoPause == AutoPauseSetting(isEnabled: false))
    }

    @Test("ignored apps persist with their names, sorted by name")
    func ignoredAppsPersist() {
        let scratch = Scratch()
        Preferences(store: scratch.defaults).ignoredApps = [
            AudioSource(id: "org.videolan.vlc", name: "VLC"),
            AudioSource(id: "com.google.Chrome", name: "Google Chrome"),
        ]
        #expect(Preferences(store: scratch.defaults).ignoredApps == [
            AudioSource(id: "com.google.Chrome", name: "Google Chrome"),
            AudioSource(id: "org.videolan.vlc", name: "VLC"),
        ])
    }

    @Test("timings persist and are clamped")
    func timingsPersist() {
        let scratch = Scratch()
        #expect(Preferences(store: scratch.defaults).timings == .defaults)
        Preferences(store: scratch.defaults).timings = TimingSettings(startConfirmation: 2.5, stopGrace: 99)
        #expect(Preferences(store: scratch.defaults).timings == TimingSettings(startConfirmation: 2.5, stopGrace: 10))
        #expect(TimingSettings.defaults.fadeOutDuration == 1 && TimingSettings.defaults.fadeInDuration == 2)
        Preferences(store: scratch.defaults).timings = TimingSettings(fadeOutDuration: 0.5, fadeInDuration: 4)
        #expect(Preferences(store: scratch.defaults).timings.fadeOutDuration == 0.5)
        #expect(Preferences(store: scratch.defaults).timings.fadeInDuration == 4)
        Preferences(store: scratch.defaults).timings = TimingSettings(fadeOutDuration: 99, fadeInDuration: -1)
        #expect(Preferences(store: scratch.defaults).timings.fadeOutDuration == 5)
        #expect(Preferences(store: scratch.defaults).timings.fadeInDuration == 0)
    }

    @Test("seen apps keep the most recent first, once each, up to the limit")
    func seenApps() {
        let scratch = Scratch()
        let preferences = Preferences(store: scratch.defaults)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        preferences.recordSeen([vlc])
        preferences.recordSeen([chrome])
        preferences.recordSeen([vlc])
        #expect(Preferences(store: scratch.defaults).seenApps == [vlc, chrome])

        preferences.recordSeen((0..<60).map { AudioSource(id: "app.\($0)", name: "App \($0)") })
        #expect(preferences.seenApps.count == Preferences.seenAppsLimit)
    }

    @Test("keeping an app seen adds it at the front once, and leaves a known app where it is")
    func keepSeen() {
        let scratch = Scratch()
        let preferences = Preferences(store: scratch.defaults)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        preferences.recordSeen([vlc])
        preferences.recordSeen([chrome])

        preferences.keepSeen(vlc)
        #expect(preferences.seenApps == [chrome, vlc])
        let zoom = AudioSource(id: "us.zoom.xos", name: "zoom.us", bundlePath: "/Applications/zoom.us.app")
        preferences.keepSeen(zoom)
        #expect(preferences.seenApps == [zoom, chrome, vlc])
    }

    @Test("the apps' order defaults to the most recent first, and persists")
    func appListOrder() {
        let scratch = Scratch()
        let preferences = Preferences(store: scratch.defaults)
        #expect(preferences.appListOrder == .standard)
        #expect(preferences.appListOrder == AppListOrder(criterion: .lastPlayed, isReversed: false))

        preferences.appListOrder = AppListOrder(criterion: .state, isReversed: true)
        #expect(Preferences(store: scratch.defaults).appListOrder == AppListOrder(criterion: .state, isReversed: true))

        scratch.defaults.set("someday", forKey: "appListOrder") // from a later version
        #expect(Preferences(store: scratch.defaults).appListOrder == AppListOrder(criterion: .lastPlayed, isReversed: true))
    }

    @Test("update settings default to automatic checks and installs, and persist")
    func updateSettings() {
        let scratch = Scratch()
        let preferences = Preferences(store: scratch.defaults)
        #expect(preferences.checksForUpdatesAutomatically)
        #expect(preferences.automaticUpdates == .install)
        #expect(preferences.lastUpdateCheck == nil)
        let date = Date(timeIntervalSinceReferenceDate: 5_000)
        preferences.checksForUpdatesAutomatically = false
        preferences.automaticUpdates = .download
        preferences.lastUpdateCheck = date
        #expect(!Preferences(store: scratch.defaults).checksForUpdatesAutomatically)
        #expect(Preferences(store: scratch.defaults).automaticUpdates == .download)
        #expect(Preferences(store: scratch.defaults).lastUpdateCheck == date)

        #expect(preferences.pauseHandedOverAt == nil)
        preferences.pauseHandedOverAt = date
        #expect(Preferences(store: scratch.defaults).pauseHandedOverAt == date)
        preferences.pauseHandedOverAt = nil
        #expect(Preferences(store: scratch.defaults).pauseHandedOverAt == nil)
    }

    @Test("the earlier 'install updates automatically' switch becomes the matching choice", arguments: [
        (false, AutomaticUpdates.notify), (true, .install),
    ])
    func legacyInstallSwitch(installed: Bool, choice: AutomaticUpdates) {
        let scratch = Scratch()
        scratch.defaults.set(installed, forKey: "installsUpdatesAutomatically")
        #expect(Preferences(store: scratch.defaults).automaticUpdates == choice)
        Preferences(store: scratch.defaults).automaticUpdates = .download
        #expect(scratch.defaults.object(forKey: "installsUpdatesAutomatically") == nil)
        #expect(Preferences(store: scratch.defaults).automaticUpdates == .download)
    }

    @Test("a kept download, an expired version, the last notice and the last version persist")
    func updateRecords() {
        let scratch = Scratch()
        let preferences = Preferences(store: scratch.defaults)
        #expect(preferences.downloadedUpdate == nil)
        let download = DownloadedUpdate(version: "0.3.8", sha256: String(repeating: "ab", count: 32),
                                        downloadedAt: Date(timeIntervalSinceReferenceDate: 9_000))
        preferences.downloadedUpdate = download
        preferences.expiredUpdateVersion = "0.3.7"
        preferences.lastUpdateNotice = "downloaded 0.3.8"
        preferences.lastLaunchedVersion = "0.3.6"
        let reread = Preferences(store: scratch.defaults)
        #expect(reread.downloadedUpdate == download)
        #expect(reread.expiredUpdateVersion == "0.3.7")
        #expect(reread.lastUpdateNotice == "downloaded 0.3.8")
        #expect(reread.lastLaunchedVersion == "0.3.6")
        preferences.downloadedUpdate = nil
        #expect(Preferences(store: scratch.defaults).downloadedUpdate == nil)
    }

    @Test("detection defaults to audio levels and persists")
    func detectionMethod() {
        let scratch = Scratch()
        #expect(Preferences(store: scratch.defaults).detectionMethod == .audioLevels)
        Preferences(store: scratch.defaults).detectionMethod = .playbackSignals
        #expect(Preferences(store: scratch.defaults).detectionMethod == .playbackSignals)
    }

    @Test("what AntiDot mode learns about apps is remembered; the earlier list without names is dropped")
    func playbackAssertions() {
        let scratch = Scratch()
        scratch.defaults.set(["com.google.Chrome"], forKey: "announcingApps")
        #expect(Preferences(store: scratch.defaults).playbackAssertions.isEmpty)

        let learned = [
            "com.google.Chrome": AnnouncedAssertions(system: ["Playing audio"], display: ["Video Wake Lock"]),
            "com.apple.Safari": AnnouncedAssertions(display: ["com.apple.WebCore: HTMLMediaElement playback"]),
        ]
        Preferences(store: scratch.defaults).playbackAssertions = learned
        #expect(Preferences(store: scratch.defaults).playbackAssertions == learned)
        #expect(scratch.defaults.object(forKey: "announcingApps") == nil)
    }

    @Test("the earlier 'measure audio levels: off' setting becomes open streams only")
    func legacyMeasuringOff() {
        let scratch = Scratch()
        scratch.defaults.set(false, forKey: "measuresAudioLevels")
        #expect(Preferences(store: scratch.defaults).detectionMethod == .openStreams)
        Preferences(store: scratch.defaults).detectionMethod = .audioLevels
        #expect(scratch.defaults.object(forKey: "measuresAudioLevels") == nil)
    }

    @Test("the chosen music player persists; none is chosen at first")
    func musicPlayer() {
        let scratch = Scratch()
        #expect(Preferences(store: scratch.defaults).musicPlayer == nil)
        Preferences(store: scratch.defaults).musicPlayer = "com.example.player"
        #expect(Preferences(store: scratch.defaults).musicPlayer == "com.example.player")
    }

    @Test("someone updating from before the choice keeps the former player")
    func updatingKeepsFormerPlayer() {
        let scratch = Scratch()
        scratch.defaults.set("0.3.11", forKey: "lastLaunchedVersion")
        Preferences(store: scratch.defaults).keepFormerPlayer("com.example.former")
        #expect(Preferences(store: scratch.defaults).musicPlayer == "com.example.former")
    }

    @Test("on a Mac where AutoHush never ran, no player is chosen, even on later launches")
    func newUserIsAsked() {
        let scratch = Scratch()
        let preferences = Preferences(store: scratch.defaults)
        preferences.keepFormerPlayer("com.example.former")
        #expect(preferences.musicPlayer == nil)
        // The first launch stores settings of its own; the user still hasn't chosen.
        preferences.lastLaunchedVersion = "0.4.0"
        preferences.keepFormerPlayer("com.example.former")
        #expect(preferences.musicPlayer == nil)
    }

    @Test("a chosen player is never replaced by the former one")
    func choiceIsKept() {
        let scratch = Scratch()
        let preferences = Preferences(store: scratch.defaults)
        preferences.lastLaunchedVersion = "0.3.11"
        preferences.musicPlayer = "com.example.chosen"
        preferences.keepFormerPlayer("com.example.former")
        #expect(preferences.musicPlayer == "com.example.chosen")
    }
}
