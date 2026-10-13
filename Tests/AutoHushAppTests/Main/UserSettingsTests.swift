import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("UserSettings")
@MainActor
struct UserSettingsTests {
    private let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
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

    @Test("an expired snooze is cleared as the settings are read")
    func expiredSnoozeCleared() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        preferences.autoPause = AutoPauseSetting(isEnabled: true, snoozedUntil: Date().addingTimeInterval(-60))
        let settings = UserSettings(preferences: preferences)
        #expect(settings.state.autoPause == .on)
        #expect(preferences.autoPause.snoozedUntil == nil)
    }

    @Test("ignoring and un-ignoring an app is stored, and what the monitoring follows changes with it")
    func ignoreApp() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let settings = UserSettings(preferences: preferences)

        settings.setIgnored(vlc, true)
        #expect(settings.state.ignoredApps == [AudioSource(id: vlc.id, name: "VLC")])
        #expect(preferences.ignoredApps.map(\.id) == [vlc.id])
        #expect(settings.state.monitoring.ignored == [vlc.id])

        settings.setIgnored(vlc, false)
        #expect(settings.state.ignoredApps.isEmpty)
        #expect(preferences.ignoredApps.isEmpty)
        #expect(settings.state.monitoring.ignored.isEmpty)
    }

    @Test("switching an app keeps its place in the order apps played")
    func ignoringKeepsPlayedOrder() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        preferences.recordSeen([vlc])
        preferences.recordSeen([chrome])
        let settings = UserSettings(preferences: preferences)
        #expect(settings.state.seenApps == [chrome, vlc])

        settings.setIgnored(vlc, true)
        #expect(preferences.seenApps == [chrome, vlc])
        #expect(settings.state.seenApps == [chrome, vlc])
    }

    @Test("forgetting an ignored app un-ignores it and removes it from the list")
    func forgetApp() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let settings = UserSettings(preferences: preferences)
        settings.setIgnored(vlc, true)

        settings.forget(vlc)
        #expect(settings.state.ignoredApps.isEmpty)
        #expect(settings.state.seenApps.isEmpty)
        #expect(preferences.seenApps.isEmpty)
    }

    @Test("resetting the list forgets every app and ignores none")
    func forgetAll() {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        preferences.recordSeen([chrome])
        let settings = UserSettings(preferences: preferences)
        settings.setIgnored(vlc, true)
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
}
