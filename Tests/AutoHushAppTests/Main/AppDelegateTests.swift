import AppKit
import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushPlayers
import SpotifySupport
import AutoHushTestSupport

@Suite("AppDelegate")
struct AppDelegateTests {
    /// Counts bootstrap requests; the real bootstrap would script Spotify and
    /// tap real audio processes from inside the test process.
    @MainActor
    private final class BootstrapCounter {
        var count = 0
    }

    /// In-memory preferences and a downloads folder of its own, so tests
    /// never write preference files or touch AutoHush's real Caches.
    @MainActor
    private final class Scratch {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let downloads = FileManager.default.temporaryDirectory.appending(path: "AppDelegateTests-\(UUID().uuidString)")
        let notifier = MockUpdateNotifier()

        deinit {
            try? FileManager.default.removeItem(at: downloads)
        }
    }

    @MainActor
    private func makeSUT(
        _ scratch: Scratch = Scratch(),
        updateChecker: UpdateChecker = UpdateChecker { _ in throw URLError(.notConnectedToInternet) },
        updateInstaller: MockUpdateInstaller = MockUpdateInstaller()
    ) -> (AppDelegate, BootstrapCounter) {
        let counter = BootstrapCounter()
        let sut = AppDelegate(
            preferences: scratch.preferences,
            launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
            updateChecker: updateChecker,
            updateInstaller: updateInstaller,
            updateNotifier: scratch.notifier,
            updateDownloadsFolder: scratch.downloads,
            currentVersion: AppVersion("0.2.0"),
            bootstrapOverride: { counter.count += 1 }
        )
        return (sut, counter)
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

    @MainActor
    @Test("with nothing monitored, quitting doesn't wait")
    func quitsAtOnceWithoutPipeline() {
        let (sut, _) = makeSUT()
        #expect(sut.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }

    @Test("startup retries only while Spotify is not ready yet")
    func transientStartupErrors() {
        #expect(AppDelegate.isTransientStartupError(MusicPlayerError.playerNotResponding))
        #expect(AppDelegate.isTransientStartupError(MusicPlayerError.playerNotRunning))
        #expect(!AppDelegate.isTransientStartupError(MusicPlayerError.automationPermissionDenied))
        #expect(!AppDelegate.isTransientStartupError(MusicPlayerError.playerCommandFailed("OSStatus -50")))
        #expect(!AppDelegate.isTransientStartupError(StubError.failed))
    }

    @MainActor
    @Test("a newer release found by an update check is offered in the menu and Settings")
    func updateAvailable() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, updateChecker: .latestRelease("v0.3.0"))
        await sut.updates.check(userInitiated: false)
        #expect(sut.status.updateOffer == UpdateOffer(release: sut.updates.availableUpdate!, state: .available))
        #expect(sut.settingsModel.updateStatus == "Version 0.3.0 is available.")
    }

    @MainActor
    @Test("turning automatic update checks off is saved and shown in Settings")
    func automaticChecksSetting() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        sut.setChecksForUpdatesAutomatically(false)
        #expect(!scratch.preferences.checksForUpdatesAutomatically)
        #expect(!sut.settingsModel.checksForUpdatesAutomatically)
        #expect(!sut.updates.isCheckDue())
    }

    @MainActor
    @Test("a pause handed over by the AutoHush before is taken over once, and only when recent")
    func pauseHandover() {
        let now = Date()
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        // Handed over after launch, as a copy that quits for this one does.
        scratch.preferences.pauseHandedOverAt = now.addingTimeInterval(-5)
        #expect(sut.takesOverPause(now: now))
        #expect(scratch.preferences.pauseHandedOverAt == nil) // read once
        scratch.preferences.pauseHandedOverAt = now
        #expect(!sut.takesOverPause(now: now)) // only the first monitoring takes one over

        let stale = Scratch()
        stale.preferences.pauseHandedOverAt = now.addingTimeInterval(-(AppDelegate.pauseHandoverMaxAge + 1))
        #expect(!makeSUT(stale).0.takesOverPause(now: now))
        #expect(!makeSUT().0.takesOverPause(now: now))
    }

    @MainActor
    @Test("the update choice is saved and shown in Settings; it starts at installing")
    func automaticUpdatesSetting() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        #expect(sut.settingsModel.automaticUpdates == .install)
        #expect(sut.settingsModel.updateInstallNote == nil)
        sut.setAutomaticUpdates(.download)
        #expect(scratch.preferences.automaticUpdates == .download)
        #expect(sut.settingsModel.automaticUpdates == .download)
        #expect(sut.updates.mode == .download)
    }

    @MainActor
    @Test("Settings says why AutoHush can't update itself")
    func installUnavailableNote() {
        let (sut, _) = makeSUT(updateInstaller: MockUpdateInstaller(unavailability: .readOnlyLocation))
        #expect(sut.settingsModel.updateInstallNote == "AutoHush can't update itself, because it can't write to the folder it's in.")
    }
}
