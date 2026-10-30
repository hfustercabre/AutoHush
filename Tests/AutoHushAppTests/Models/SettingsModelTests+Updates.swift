import AppKit
import Observation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

extension SettingsModelTests {
    // MARK: - Updates

    @Test("beside Check Now: the version until a check, then what it found; under it, when the last one was")
    func updateRow() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        #expect(model.updateTitle == "AutoHush")
        updates.currentVersion = AppVersion("0.3.11")
        #expect(model.updateTitle == "AutoHush 0.3.11")
        #expect(model.lastCheckedNote() == nil)

        let now = Date()
        updates.lastCheck = now.addingTimeInterval(-2 * 3600)
        updates.status = "AutoHush 0.3.11 is up to date."
        #expect(model.updateTitle == "AutoHush 0.3.11 is up to date.")
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        let when = formatter.localizedString(for: now.addingTimeInterval(-2 * 3600), relativeTo: now)
        #expect(model.lastCheckedNote(now: now) == "Last checked \(when)")
    }

    @Test("the Updates row says only when the last check was until one runs in this launch, the version being About's; then what it found, with when; the version before any check")
    func updateRowShowsTheVersionOnce() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        updates.currentVersion = AppVersion("0.3.11")
        #expect(model.updateRow() == ("AutoHush 0.3.11", nil))

        let now = Date()
        updates.lastCheck = now.addingTimeInterval(-2 * 3600)
        let checked = model.lastCheckedNote(now: now)
        #expect(model.updateRow(now: now) == (checked ?? "", nil))
        updates.status = "AutoHush 0.3.11 is up to date."
        #expect(model.updateRow(now: now) == ("AutoHush 0.3.11 is up to date.", checked))
    }

    @Test("a release candidate running with Get release candidates off says the latest release is offered instead; found, a candidate says what it's a test of")
    func releaseCandidateNotes() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        updates.currentVersion = AppVersion("1.2.6")
        #expect(model.releaseCandidateNote == nil)
        updates.currentVersion = AppVersion("1.2.7-rc.1")
        #expect(model.releaseCandidateNote == "You’re on 1.2.7 RC 1, a release candidate: AutoHush offers the latest release instead.")
        updates.getsReleaseCandidates = true
        #expect(model.releaseCandidateNote == nil)

        let now = Date()
        updates.lastCheck = now.addingTimeInterval(-2 * 3600)
        updates.status = "AutoHush 1.2.7 RC 2 is available."
        updates.availableUpdate = AppRelease(version: AppVersion("1.2.7-rc.2")!, pageURL: URL(string: "https://github.com/hfustercabre/AutoHush/releases/tag/v1.2.7-rc.2")!)
        let checked = model.lastCheckedNote(now: now) ?? ""
        #expect(model.updateRow(now: now) == ("AutoHush 1.2.7 RC 2 is available.", "A test version of 1.2.7 · \(checked)"))
    }

    /// Settings' model on real updates, which find v0.3.0 and can't install
    /// it (AutoHush's folder is read-only).
    private func updateRows() -> (model: SettingsModel, updates: UpdateController, notifier: MockUpdateNotifier,
                                  preferences: Preferences, folder: TemporaryFolder) {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let notifier = MockUpdateNotifier()
        let folder = TemporaryFolder("SettingsModelTests", create: false)
        let updates = UpdateController(
            system: UpdateController.System(checker: .latestRelease("v0.3.0"), installer: MockUpdateInstaller(unavailability: .readOnlyLocation),
                                            notifier: notifier, downloadsFolder: folder.url, currentVersion: AppVersion("0.2.0")),
            preferences: preferences, isQuietMoment: { false }, quit: {}, onOffer: { _ in }
        )
        let model = SettingsModel(settings: .inMemory(), updates: updates, actions: actions,
                                  launchAtLoginController: MockLaunchAtLoginController(isEnabled: false))
        return (model, updates, notifier, preferences, folder)
    }

    /// Whether what `read` reads is told of `change`, as a view drawn from it is.
    private func follows(_ read: () -> Void, after change: () async -> Void) async -> Bool {
        let changed = Locked(false)
        withObservationTracking(read) { changed.value = true }
        await change()
        return changed.value
    }

    @Test("the update rows read the updates themselves, with no one passing them on: the version, and no check yet")
    func updateRowsReadTheUpdates() {
        let bench = updateRows()
        #expect(bench.model.currentVersion == "0.2.0" && bench.model.updateStatus == nil && bench.model.lastUpdateCheck == nil)
    }

    @Test("the update rows' install note is as at launch")
    func updateRowsInstallNote() {
        let bench = updateRows()
        #expect(bench.model.updateInstallNote == UpdateInstallUnavailability.readOnlyLocation.explanation)
    }

    @Test("a copy that can't install itself shows and explains Notify me, whatever was chosen before")
    func updateRowsShowNotifyWhenInstallUnavailable() {
        let bench = updateRows()
        bench.updates.setMode(.install)
        #expect(bench.model.automaticUpdates == .install && bench.model.shownAutomaticUpdates == .notify)
    }

    @Test("the update rows follow notifications turned off")
    func updateRowsFollowNotifications() async {
        let bench = updateRows()
        bench.notifier.currentPermission = .off
        #expect(await follows({ _ = bench.model.notificationsOff }, after: { await bench.updates.followNotificationPermission() }))
        #expect(bench.model.notificationsOff)
    }

    @Test("the update rows follow a check's status and when it ran")
    func updateRowsFollowTheCheck() async {
        let bench = updateRows()
        #expect(await follows({ _ = bench.model.updateStatus }, after: { await bench.updates.check(userInitiated: false) }))
        #expect(bench.model.updateStatus == "Version 0.3.0 is available." && bench.model.lastUpdateCheck == bench.preferences.lastUpdateCheck)
    }

    @Test("the update rows follow the update settings")
    func updateRowsFollowTheSettings() async {
        let bench = updateRows()
        #expect(await follows({ _ = bench.model.automaticUpdates }, after: { bench.updates.setMode(.notify) }))
        #expect(bench.model.automaticUpdates == .notify)
        #expect(await follows({ _ = bench.model.checksForUpdatesAutomatically }, after: { bench.updates.setChecksAutomatically(false) }))
        #expect(!bench.model.checksForUpdatesAutomatically)
    }

    @Test("Volume's note says why leveling can't be changed as a fragment, without a period; nothing while it can")
    func levelingUnavailableNote() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        #expect(model.levelingUnavailableNote == nil)
        model.setAntiDotMode(true)
        #expect(model.levelingUnavailableNote == "Off in AntiDot mode")
    }
}
