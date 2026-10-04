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

    @Test("update settings default to automatic checks and installs, and persist")
    func updateSettings() {
        let scratch = Scratch()
        let preferences = Preferences(store: scratch.defaults)
        #expect(preferences.checksForUpdatesAutomatically)
        #expect(preferences.installsUpdatesAutomatically)
        #expect(preferences.lastUpdateCheck == nil)
        let date = Date(timeIntervalSinceReferenceDate: 5_000)
        preferences.checksForUpdatesAutomatically = false
        preferences.installsUpdatesAutomatically = false
        preferences.lastUpdateCheck = date
        #expect(!Preferences(store: scratch.defaults).checksForUpdatesAutomatically)
        #expect(!Preferences(store: scratch.defaults).installsUpdatesAutomatically)
        #expect(Preferences(store: scratch.defaults).lastUpdateCheck == date)
    }

    @Test("detection defaults to audio levels and persists")
    func detectionMethod() {
        let scratch = Scratch()
        #expect(Preferences(store: scratch.defaults).detectionMethod == .audioLevels)
        Preferences(store: scratch.defaults).detectionMethod = .playbackSignals
        #expect(Preferences(store: scratch.defaults).detectionMethod == .playbackSignals)
    }

    @Test("apps announcing playback are remembered")
    func announcingApps() {
        let scratch = Scratch()
        #expect(Preferences(store: scratch.defaults).announcingApps.isEmpty)
        Preferences(store: scratch.defaults).announcingApps = ["org.videolan.vlc", "com.google.Chrome"]
        #expect(Preferences(store: scratch.defaults).announcingApps == ["org.videolan.vlc", "com.google.Chrome"])
    }

    @Test("the earlier 'measure audio levels: off' setting becomes open streams only")
    func legacyMeasuringOff() {
        let scratch = Scratch()
        scratch.defaults.set(false, forKey: "measuresAudioLevels")
        #expect(Preferences(store: scratch.defaults).detectionMethod == .openStreams)
        Preferences(store: scratch.defaults).detectionMethod = .audioLevels
        #expect(scratch.defaults.object(forKey: "measuresAudioLevels") == nil)
    }
}
