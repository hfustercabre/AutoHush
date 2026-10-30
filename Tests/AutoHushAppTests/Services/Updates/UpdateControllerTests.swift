import AppKit
import Foundation
import Observation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("UpdateController", .waitsTimeLimit)
@MainActor
struct UpdateControllerTests {
    /// Records what the controller reports and the alerts it shows (at once,
    /// answered with `answer`), and keeps its preferences, its downloads
    /// folder and its clock.
    @MainActor
    final class Harness {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let installer: MockUpdateInstaller
        let notifier = MockUpdateNotifier()
        /// Whether AutoHush could restart unnoticed right now.
        let quiet: Locked<Bool>
        private let scratchFolder = TemporaryFolder("UpdateControllerTests", create: false)
        var folder: URL { scratchFolder.url }
        var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var offers: [UpdateOffer?] = []
        /// Each status Settings showed, as the next replaced it (`followStatus`).
        private var replacedStatuses: [String] = []
        var opened: [URL] = []
        var quits = 0
        /// How many times the update settings changed, as Settings follows them.
        var settingsChanges = 0
        var alerts: [NSAlert] = []
        /// The button that closes the next alert.
        var answer = NSApplication.ModalResponse.alertFirstButtonReturn
        /// How many times the menu was closed for an alert.
        var menuClosings = 0
        /// Runs as each status gives way to the next, with the one it replaces.
        var asStatusChanges: @MainActor (_ replaced: String?) -> Void = { _ in }
        private(set) var controller: UpdateController!

        init(
            checker: UpdateChecker,
            installer: MockUpdateInstaller = MockUpdateInstaller(),
            quiet: Locked<Bool> = Locked(true),
            currentVersion: AppVersion? = AppVersion("0.2.0"),
            mode: AutomaticUpdates = .install
        ) {
            self.installer = installer
            self.quiet = quiet
            preferences.automaticUpdates = mode
            controller = UpdateController(
                system: UpdateController.System(checker: checker, installer: installer, notifier: notifier,
                                                downloadsFolder: folder, currentVersion: currentVersion),
                preferences: preferences,
                // Weak: an automatic run a setting started may end after its test.
                now: { [weak self] in self?.now ?? Date(timeIntervalSinceReferenceDate: 800_000_000) },
                isQuietMoment: { quiet.value },
                quit: { [weak self] in self?.quits += 1 },
                openURL: { [weak self] in self?.opened.append($0) },
                onOffer: { [weak self] in self?.offers.append($0) }
            )
            followSettings()
            followStatus()
            controller.beforePresenting = { [weak self] in self?.menuClosings += 1 }
            controller.showAlert = { $0() }
            controller.runAlert = { [weak self] alert in
                self?.alerts.append(alert)
                return self?.answer ?? .cancel
            }
        }

        /// Counts each change to the settings Settings reads, as it's made.
        private func followSettings() {
            withObservationTracking {
                _ = (controller.checksAutomatically, controller.mode)
            } onChange: { [weak self] in
                MainActor.assumeIsolated { // changed on the main actor, the controller's
                    self?.settingsChanges += 1
                    self?.followSettings()
                }
            }
        }

        /// Follows the status Settings reads. Observation tells a change
        /// before it's made, so each status is noted as the next replaces it.
        private func followStatus() {
            withObservationTracking {
                _ = controller.status
            } onChange: { [weak self] in
                MainActor.assumeIsolated { // changed on the main actor, the controller's
                    guard let self else { return }
                    let replaced = self.controller.status
                    if let replaced { self.replacedStatuses.append(replaced) }
                    self.asStatusChanges(replaced)
                    self.followStatus()
                }
            }
        }

        /// The statuses Settings showed, in turn, the one it shows now last.
        var statuses: [String] { replacedStatuses + (controller.status.map { [$0] } ?? []) }

        /// The update the menu offers now.
        var offer: UpdateOffer? { offers.last ?? nil }

        /// The files in the downloads folder.
        var keptFiles: [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        }

        /// How many downloads were asked for.
        var downloads: Int { installer.calls.filter { $0.hasPrefix("download") }.count }

        /// Makes the next automatic run check again.
        func makeCheckDue() { preferences.lastUpdateCheck = nil }
    }

    let v030 = AppVersion("0.3.0")!

    // MARK: - Checking

    @Test("turning automatic checks off is stored and shown; no check is due then; turned on again, it checks at once when one is due")
    func automaticChecksSetting() async {
        let h = Harness(checker: .latestRelease("v0.2.0"))
        h.controller.setChecksAutomatically(false)
        #expect(!h.preferences.checksForUpdatesAutomatically)
        #expect(h.settingsChanges == 1)
        #expect(!h.controller.isCheckDue())

        h.controller.setChecksAutomatically(true) // none has run yet: one is due
        await TestWait.until { h.controller.status == "AutoHush 0.2.0 is up to date." }
        #expect(h.statuses == ["Checking…", "AutoHush 0.2.0 is up to date."])
        #expect(h.settingsChanges == 2)
    }

    @Test("the update choice is stored and shown; a choice that notifies asks for permission, if not answered yet")
    func automaticUpdatesSetting() {
        let h = Harness(checker: .latestRelease("v0.2.0"))
        h.controller.setMode(.install)
        #expect(h.notifier.permissionRequests == 0)
        h.controller.setMode(.download)
        #expect(h.preferences.automaticUpdates == .download)
        #expect(h.controller.mode == .download)
        #expect(h.settingsChanges == 2)
        #expect(h.notifier.permissionRequests == 1)
    }

    @Test("a check asked for while one is under way doesn't start another, and shows the result (Check for Updates… during an automatic check)")
    func overlappingChecks() async {
        // The fetches, counted, each held until the gate opens.
        let fetches = Locked(0), held = Gate()
        let h = Harness(checker: .latestRelease({ "v0.2.0" }, onFetch: {
            fetches.increment()
            await held.wait()
        }))

        let automatic = Task { await h.controller.check(userInitiated: false) }
        await TestWait.until { fetches.value == 1 }
        let menu = Task { await h.controller.checkNow() }
        await TestWait.until { h.controller.resultWanted } // the menu's check joined it
        await held.open()
        await automatic.value
        await menu.value

        #expect(fetches.value == 1)
        #expect(h.statuses == ["Checking…", "AutoHush 0.2.0 is up to date."])
        #expect(h.alerts.map(\.messageText) == ["AutoHush Is Up to Date"])
        #expect(h.menuClosings == 1)
    }

    @Test("a check asked for just as an automatic check ends starts afresh, and shows its own result")
    func checkAskedForAsOneEnds() async {
        let fetches = Locked(0)
        let h = Harness(checker: .latestRelease({ "v0.2.0" }, onFetch: { fetches.increment() }))
        // Asked for once an automatic check has read that nobody asked, before its caller is back:
        // as its result replaces "Checking…".
        h.asStatusChanges = { replaced in
            guard replaced == "Checking…" else { return }
            h.asStatusChanges = { _ in }
            Task { await h.controller.checkNow() }
        }
        await h.controller.check(userInitiated: false)
        await TestWait.until { h.alerts.count == 1 }
        #expect(fetches.value == 2)
        #expect(h.alerts.map(\.messageText) == ["AutoHush Is Up to Date"])
        #expect(h.menuClosings == 1)
    }

    @Test("a check that finds a newer release offers it and remembers when it ran")
    func updateAvailable() async {
        let h = Harness(checker: .latestRelease("v0.3.0"))
        await h.controller.check(userInitiated: false)
        #expect(h.controller.availableUpdate?.version == v030)
        #expect(h.offer?.release.version == v030)
        #expect(h.offer?.state == .available)
        #expect(h.statuses == ["Checking…", "Version 0.3.0 is available."])
        #expect(h.preferences.lastUpdateCheck == h.now)
    }

    @Test("an up-to-date check clears an earlier offer and withdraws its notification")
    func upToDate() async {
        let latest = Locked("v0.3.0")
        let h = Harness(checker: .latestRelease { latest.value }, mode: .notify)
        await h.controller.runAutomaticTasks()
        #expect(h.offer != nil)
        #expect(h.notifier.announced == [.available(v030, running: AppVersion("0.2.0")!)])

        latest.value = "v0.2.0" // the newer release was withdrawn
        await h.controller.check(userInitiated: false)
        #expect(h.controller.availableUpdate == nil)
        #expect(h.offers.last == .some(nil))
        #expect(h.notifier.withdrawals == 1)
        #expect(h.controller.status == "AutoHush 0.2.0 is up to date.")
    }

    @Test("an up-to-date check leaves an \"updated to\" notification alone")
    func keepsUpdatedNotice() async {
        let h = Harness(checker: .latestRelease("v0.2.0"))
        h.preferences.lastUpdateNotice = "installed 0.2.0"
        await h.controller.check(userInitiated: false)
        #expect(h.notifier.withdrawals == 0)
    }

    @Test("a failed automatic check is quiet and doesn't count as a check")
    func failedCheck() async {
        let h = Harness(checker: .offline)
        await h.controller.check(userInitiated: false)
        #expect(h.controller.status == "Couldn’t check for updates.")
        #expect(h.preferences.lastUpdateCheck == nil)
        #expect(h.offers.isEmpty)
    }

    @Test("without a known app version nothing is asked")
    func unknownVersion() async {
        let h = Harness(checker: .offline, currentVersion: nil)
        await h.controller.check(userInitiated: false)
        #expect(h.statuses == ["AutoHush’s version is unknown."])
    }
}
