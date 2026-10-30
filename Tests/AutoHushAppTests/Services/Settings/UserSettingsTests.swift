import Foundation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("UserSettings", .waitsTimeLimit)
@MainActor
struct UserSettingsTests {
    private let viewer = AudioSource(id: "org.example.viewer", name: "Viewer", bundlePath: "/Applications/Viewer.app")
    private let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome", bundlePath: "/Applications/Google Chrome.app")

    @Test("toggling Auto-Pause switches it off and on again, and persists")
    func toggleAutoPause() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let settings = UserSettings(preferences: preferences)
        #expect(settings.state.autoPause == .on && settings.state.autoPauseActive)

        settings.toggleAutoPause()
        #expect(settings.state.autoPause == .off && !settings.state.autoPauseActive)
        #expect(preferences.autoPause == AutoPauseSetting(isEnabled: false))

        settings.toggleAutoPause()
        #expect(settings.state.autoPause == .on && settings.state.autoPauseActive)
    }

    @Test("snoozing turns Auto-Pause off until the end; toggling ends the snooze")
    func snoozeThenToggle() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let settings = UserSettings(preferences: preferences)
        let now = Date()

        settings.snooze(.oneHour, now: now)
        guard case .snoozed = settings.state.autoPause else {
            Issue.record("expected snoozed, got \(settings.state.autoPause)")
            return
        }
        #expect(!settings.state.autoPauseActive)
        #expect(preferences.autoPause.snoozedUntil == AutoPauseSnooze.oneHour.endDate(from: now))

        settings.toggleAutoPause(now: now)
        #expect(settings.state.autoPause == .on)
        #expect(preferences.autoPause.snoozedUntil == nil)
    }

    @Test("an expired snooze is cleared as the settings are read, and one running out meanwhile once its time is up")
    func expiredSnoozeCleared() async {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        preferences.autoPause = AutoPauseSetting(isEnabled: true, snoozedUntil: Date().addingTimeInterval(-60))
        let settings = UserSettings(preferences: preferences)
        #expect(settings.state.autoPause == .on)
        #expect(preferences.autoPause.snoozedUntil == nil)

        // Turned off for five minutes, a second before the end of them (a
        // moment that a loaded runner can't outlast between two lines).
        settings.snooze(.fiveMinutes, now: Date().addingTimeInterval(-AutoPauseSnooze.fiveMinutes.duration + 1))
        #expect(!settings.isAutoPauseActive)
        await TestWait.until { settings.isAutoPauseActive }
        #expect(settings.state.autoPause == .on)
        #expect(preferences.autoPause.snoozedUntil == nil)
    }

    @Test("a noted setting comes back; a 'turn off for' that ran out comes back as on")
    func restoreAutoPause() {
        let settings = UserSettings.inMemory()
        let now = Date()
        settings.restoreAutoPause(AutoPauseSetting(isEnabled: true, snoozedUntil: now.addingTimeInterval(600)), now: now)
        #expect(!settings.isAutoPauseActive && settings.autoPauseSetting.snoozedUntil != nil)
        settings.restoreAutoPause(AutoPauseSetting(isEnabled: true, snoozedUntil: now.addingTimeInterval(-1)), now: now)
        #expect(settings.isAutoPauseActive && settings.autoPauseSetting == AutoPauseSetting())
    }

    @Test("ignoring and un-ignoring an app is stored, and what the monitoring follows changes with it")
    func ignoreApp() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let settings = UserSettings(preferences: preferences)

        settings.setIgnored(viewer, true)
        #expect(settings.state.ignoredApps == [AudioSource(id: viewer.id, name: "Viewer")])
        #expect(preferences.ignoredApps.map(\.id) == [viewer.id])
        #expect(settings.state.monitoring.ignored == [viewer.id])

        settings.setIgnored(viewer, false)
        #expect(settings.state.ignoredApps.isEmpty)
        #expect(preferences.ignoredApps.isEmpty)
        #expect(settings.state.monitoring.ignored.isEmpty)
    }

    @Test("switching an app keeps its place in the order apps played")
    func ignoringKeepsPlayedOrder() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        preferences.recordSeen([viewer])
        preferences.recordSeen([chrome])
        let settings = UserSettings(preferences: preferences)
        #expect(settings.state.seenApps == [chrome, viewer])

        settings.setIgnored(viewer, true)
        #expect(preferences.seenApps == [chrome, viewer])
        #expect(settings.state.seenApps == [chrome, viewer])
    }

    @Test("forgetting an ignored app un-ignores it and removes it from the list")
    func forgetApp() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let settings = UserSettings(preferences: preferences)
        settings.setIgnored(viewer, true)

        settings.forget(viewer)
        #expect(settings.state.ignoredApps.isEmpty)
        #expect(settings.state.seenApps.isEmpty)
        #expect(preferences.seenApps.isEmpty)
    }

    @Test("an app that plays only the volume sound is ignored once; stopped ignoring, it stays so until the list is reset")
    func ignoreByDefault() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let settings = UserSettings(preferences: preferences)
        let display = AudioSource(id: "com.example.display", name: "Display Tool", bundlePath: "/Applications/Display Tool.app")
        settings.ignoreByDefault(display)
        #expect(settings.state.ignoredApps.map(\.id) == [display.id])
        #expect(settings.state.monitoring.ignored == [display.id])
        #expect(settings.state.seenApps.map(\.id) == [display.id]) // listed in Settings → Sound Sources, with its icon

        settings.setIgnored(display, false)
        settings.ignoreByDefault(display) // opened again
        #expect(settings.state.ignoredApps.isEmpty)
        #expect(UserSettings(preferences: preferences).state.ignoredApps.isEmpty) // after a relaunch too

        // Reset List…: the next time it runs, it's ignored again.
        settings.forgetAll()
        settings.ignoreByDefault(display)
        #expect(settings.state.ignoredApps.map(\.id) == [display.id])
    }

    @Test("an app the user already ignores is only noted, not added twice")
    func ignoreByDefaultAlreadyIgnored() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let settings = UserSettings(preferences: preferences)
        settings.setIgnored(viewer, true)
        settings.ignoreByDefault(viewer)
        #expect(settings.state.ignoredApps.map(\.id) == [viewer.id])
        #expect(preferences.appsIgnoredByDefault == [viewer.id])
    }

    @Test("resetting the list forgets every app and ignores none")
    func forgetAll() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        preferences.recordSeen([chrome])
        let settings = UserSettings(preferences: preferences)
        settings.setIgnored(viewer, true)
        #expect(settings.state.seenApps.count == 2)

        settings.forgetAll()
        #expect(settings.state.ignoredApps.isEmpty && settings.state.seenApps.isEmpty)
        #expect(preferences.ignoredApps.isEmpty && preferences.seenApps.isEmpty)
    }

    @Test("the apps the monitoring heard are picked up once it says so")
    func appsSeenChanged() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let settings = UserSettings(preferences: preferences)
        preferences.recordSeen([chrome]) // the player session records them
        #expect(settings.state.seenApps.isEmpty)
        settings.appsSeenChanged()
        #expect(settings.state.seenApps == [chrome])
    }

    @Test("the timings, the detection method and the list's order are stored and shown")
    func detectionAndOrder() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let settings = UserSettings(preferences: preferences)

        settings.setTimings(TimingSettings(stopGrace: 4))
        #expect(preferences.timings.stopGrace == 4)
        #expect(settings.state.timings.stopGrace == 4)
        #expect(settings.state.monitoring.timings.stopGrace == 4)

        settings.setDetectionMethod(.playbackSignals)
        #expect(preferences.detectionMethod == .playbackSignals)
        #expect(settings.state.monitoring.detection == .playbackSignals)

        settings.setListOrder(AppListOrder(criterion: .name, isReversed: true))
        #expect(preferences.appListOrder == AppListOrder(criterion: .name, isReversed: true))
        #expect(UserSettings(preferences: preferences).state.listOrder == AppListOrder(criterion: .name, isReversed: true))
    }

    @Test("each change is told once; a setting set to what it is isn't a change")
    func changesTold() {
        let settings = UserSettings.inMemory()
        let told = CallLog()
        settings.didChange = { told.calls.append("autoPause \($0.autoPause)") }

        settings.setAutoPause(false)
        settings.setAutoPause(false)
        settings.setDetectionMethod(.audioLevels) // already
        #expect(told.calls == ["autoPause off"])
    }

    @Test("the log says each timing that changed, by its name in Settings, from what to what")
    func timingChanges() {
        var new = TimingSettings.defaults
        #expect(UserSettings.changes(from: .defaults, to: new).isEmpty)
        new.startConfirmation = 1.25
        new.silenceThresholdDB = -45
        new.fadesEnabled = false
        // Seconds in the region's numbers, as the log writes them ("0,5" in Spain's).
        let seconds = { (value: Double) in value.formatted(.number.precision(.fractionLength(0...2))) }
        #expect(UserSettings.changes(from: .defaults, to: new) == [
            "Pause playback after: \(seconds(0.5)) s → \(seconds(1.25)) s",
            "Silence threshold: -60 dBFS → -45 dBFS",
            "Fade the music: off",
        ])
    }
}
