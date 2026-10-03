import Foundation
import Testing
@testable import AutoHush

@Suite("AppDelegate")
struct AppDelegateTests {
    /// Counts bootstrap requests; the real bootstrap would script Spotify and
    /// tap real audio processes from inside the test process.
    @MainActor
    private final class BootstrapCounter {
        var count = 0
    }

    /// In-memory preferences, so tests never write preference files.
    @MainActor
    private final class Scratch {
        let preferences = Preferences(store: InMemoryPreferenceStore())
    }

    @MainActor
    private func makeSUT(
        _ scratch: Scratch = Scratch(),
        updateChecker: UpdateChecker = UpdateChecker { _ in throw URLError(.notConnectedToInternet) }
    ) -> (AppDelegate, BootstrapCounter) {
        let counter = BootstrapCounter()
        let sut = AppDelegate(
            preferences: scratch.preferences,
            launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
            updateChecker: updateChecker,
            currentVersion: AppVersion("0.2.0"),
            bootstrapOverride: { counter.count += 1 }
        )
        return (sut, counter)
    }

    private static func releaseChecker(_ tag: String) -> UpdateChecker {
        UpdateChecker { request in
            let body = #"{"tag_name": "\#(tag)", "html_url": "https://github.com/hfustercabre/AutoHush/releases/tag/\#(tag)"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    @MainActor
    @Test("non-Spotify launch does not change health state or re-bootstrap")
    func nonSpotifyLaunchDoesNothing() {
        let (sut, bootstraps) = makeSUT()

        #expect(sut.status.health == .starting)
        sut.handleApplicationDidLaunch(bundleIdentifier: "org.videolan.vlc")
        #expect(sut.status.health == .starting)
        #expect(bootstraps.count == 0)
    }

    @MainActor
    @Test("Spotify launch sets app back to starting and re-bootstraps")
    func spotifyLaunchSetsStartingState() {
        let (sut, bootstraps) = makeSUT()
        sut.setHealth(.degraded("Spotify is not running"))

        sut.handleApplicationDidLaunch(bundleIdentifier: "com.spotify.client")

        #expect(sut.status.health == .starting)
        #expect(bootstraps.count == 1)
    }

    @MainActor
    @Test("nil bundle identifier does nothing")
    func nilBundleIdentifierDoesNothing() {
        let (sut, bootstraps) = makeSUT()
        sut.setHealth(.ready)

        sut.handleApplicationDidLaunch(bundleIdentifier: nil)

        #expect(sut.status.health == .ready)
        #expect(bootstraps.count == 0)
    }

    // MARK: - Auto-pause and ignored apps

    @MainActor
    @Test("toggling auto-pause switches it off and on again, and persists")
    func toggleAutoPause() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        #expect(sut.status.autoPause == .on)

        sut.toggleAutoPause()
        #expect(sut.status.autoPause == .off)
        #expect(scratch.preferences.autoPause == AutoPauseSetting(isEnabled: false))

        sut.toggleAutoPause()
        #expect(sut.status.autoPause == .on)
    }

    @MainActor
    @Test("snoozing turns auto-pause off until the end; toggling ends the snooze")
    func snoozeThenToggle() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let now = Date()

        sut.snooze(.oneHour, now: now)
        guard case .snoozed = sut.status.autoPause else {
            Issue.record("expected snoozed, got \(sut.status.autoPause)")
            return
        }
        #expect(scratch.preferences.autoPause.snoozedUntil == AutoPauseSnooze.oneHour.endDate(from: now))

        sut.toggleAutoPause(now: now)
        #expect(sut.status.autoPause == .on)
        #expect(scratch.preferences.autoPause.snoozedUntil == nil)
    }

    @MainActor
    @Test("an expired snooze is cleared at launch")
    func expiredSnoozeCleared() {
        let scratch = Scratch()
        scratch.preferences.autoPause = AutoPauseSetting(isEnabled: true, snoozedUntil: Date().addingTimeInterval(-60))
        let (sut, _) = makeSUT(scratch)
        #expect(sut.status.autoPause == .on)
        #expect(scratch.preferences.autoPause.snoozedUntil == nil)
    }

    @MainActor
    @Test("ignoring and un-ignoring an app updates the menu and the preferences")
    func ignoreApp() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")

        sut.setIgnored(vlc, true)
        #expect(sut.status.ignoredApps == [AudioSource(id: "org.videolan.vlc", name: "VLC")])
        #expect(scratch.preferences.ignoredApps.map(\.id) == ["org.videolan.vlc"])

        sut.setIgnored(vlc, false)
        #expect(sut.status.ignoredApps.isEmpty)
        #expect(scratch.preferences.ignoredApps.isEmpty)
    }

    // MARK: - Settings and updates

    @MainActor
    @Test("the Settings model mirrors auto-pause, apps and timings")
    func settingsModelMirrorsState() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")

        sut.snooze(.oneHour)
        #expect(!sut.settingsModel.isAutoPauseOn)
        #expect(sut.settingsModel.autoPauseNote?.hasPrefix("Turned off until") == true)
        sut.setAutoPause(true)
        #expect(sut.settingsModel.isAutoPauseOn && sut.settingsModel.autoPauseNote == nil)

        sut.setIgnored(vlc, true)
        #expect(sut.settingsModel.apps.map(\.id) == ["org.videolan.vlc"])
        #expect(sut.settingsModel.apps.first?.isIgnored == true)

        sut.setTimings(TimingSettings(stopGrace: 4))
        #expect(scratch.preferences.timings.stopGrace == 4)
        #expect(sut.settingsModel.timings.stopGrace == 4)
    }

    @MainActor
    @Test("forgetting an ignored app un-ignores it and removes it from the list")
    func forgetApp() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        sut.setIgnored(vlc, true)

        sut.forget(vlc)
        #expect(sut.status.ignoredApps.isEmpty)
        #expect(scratch.preferences.seenApps.isEmpty)
        #expect(sut.settingsModel.apps.isEmpty)
    }

    @MainActor
    @Test("resetting the list forgets every app and ignores none")
    func forgetAllApps() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome", bundlePath: "/Applications/Google Chrome.app")
        scratch.preferences.recordSeen([chrome])
        sut.setIgnored(vlc, true)
        #expect(sut.settingsModel.apps.count == 2)

        sut.forgetAllApps()
        #expect(sut.status.ignoredApps.isEmpty)
        #expect(scratch.preferences.ignoredApps.isEmpty)
        #expect(scratch.preferences.seenApps.isEmpty)
        #expect(sut.settingsModel.apps.isEmpty)
    }

    @Test("startup retries only while Spotify is not ready yet")
    func transientStartupErrors() {
        #expect(AppDelegate.isTransientStartupError(AutoHushError.playerNotResponding))
        #expect(AppDelegate.isTransientStartupError(AutoHushError.playerNotRunning))
        #expect(!AppDelegate.isTransientStartupError(AutoHushError.automationPermissionDenied))
        #expect(!AppDelegate.isTransientStartupError(AutoHushError.playerCommandFailed("OSStatus -50")))
        #expect(!AppDelegate.isTransientStartupError(StubError.failed))
    }

    @MainActor
    @Test("an automatic check that finds a newer release offers it in the menu")
    func updateAvailable() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, updateChecker: Self.releaseChecker("v0.3.0"))
        await sut.checkForUpdates(userInitiated: false)
        #expect(sut.status.availableUpdate?.version == AppVersion("0.3.0"))
        #expect(sut.settingsModel.updateStatus == "Version 0.3.0 is available.")
        #expect(scratch.preferences.lastUpdateCheck != nil)
    }

    @MainActor
    @Test("an up-to-date check clears the offer")
    func upToDate() async {
        let (sut, _) = makeSUT(updateChecker: Self.releaseChecker("v0.2.0"))
        sut.setAvailableUpdate(AppRelease(version: AppVersion("0.3.0")!, pageURL: URL(string: "https://example.com")!))
        await sut.checkForUpdates(userInitiated: false)
        #expect(sut.status.availableUpdate == nil)
        #expect(sut.settingsModel.updateStatus == "AutoHush 0.2.0 is up to date.")
    }

    @MainActor
    @Test("a failed automatic check is quiet")
    func failedCheck() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        await sut.checkForUpdates(userInitiated: false)
        #expect(sut.settingsModel.updateStatus == "Couldn't check for updates.")
        #expect(scratch.preferences.lastUpdateCheck == nil)
    }

    @MainActor
    @Test("automatic checks are due daily, and never when turned off")
    func updateCheckDue() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let now = Date()
        #expect(sut.isUpdateCheckDue(now: now))
        scratch.preferences.lastUpdateCheck = now.addingTimeInterval(-3600)
        #expect(!sut.isUpdateCheckDue(now: now))
        scratch.preferences.lastUpdateCheck = now.addingTimeInterval(-25 * 3600)
        #expect(sut.isUpdateCheckDue(now: now))
        sut.setChecksForUpdatesAutomatically(false)
        #expect(!sut.isUpdateCheckDue(now: now))
    }
}
