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
    private final class Harness {
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

    private let v030 = AppVersion("0.3.0")!

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

    // MARK: - Notify me

    @Test("\"Notify me\" announces a new version once, and the menu offers it")
    func notifies() async {
        let h = Harness(checker: .latestRelease("v0.3.0"), mode: .notify)
        await h.controller.runAutomaticTasks()
        await h.controller.runAutomaticTasks()
        #expect(h.notifier.announced == [.available(v030, running: AppVersion("0.2.0")!)])
        #expect(h.offer?.state == .available)
        #expect(h.installer.calls.isEmpty)
    }

    @Test("a newer release is announced again")
    func announcesNewerRelease() async {
        let latest = Locked("v0.3.0")
        let h = Harness(checker: .latestRelease { latest.value }, mode: .notify)
        await h.controller.runAutomaticTasks()
        latest.value = "v0.3.1"
        h.makeCheckDue()
        await h.controller.runAutomaticTasks()
        #expect(h.notifier.announced.map(\.key) == ["available 0.3.0", "available 0.3.1"])
    }

    // MARK: - Download it and notify me

    @Test("\"Download it and notify me\" keeps the download, outside Low Data Mode, and announces it once")
    func downloads() async {
        let h = Harness(checker: .latestRelease("v0.3.0"), mode: .download)
        await h.controller.runAutomaticTasks()
        await h.controller.runAutomaticTasks()

        #expect(h.installer.calls == ["download 0.3.0"])
        #expect(h.installer.lowDataModeAllowed == [false])
        #expect(h.keptFiles == ["AutoHush-0.3.0.dmg"])
        #expect(h.preferences.downloadedUpdate?.version == "0.3.0")
        #expect(h.preferences.downloadedUpdate?.downloadedAt == h.now)
        #expect(h.notifier.announced == [.downloaded(v030)])
        #expect(h.offer?.state == .downloaded)
        #expect(h.statuses.suffix(2) == ["Downloading version 0.3.0…", "Version 0.3.0 is downloaded and ready to install."])
        #expect(h.quits == 0)
    }

    @Test("installing a kept download uses it, then deletes it")
    func installsKeptDownload() async throws {
        let h = Harness(checker: .latestRelease("v0.3.0"), mode: .download)
        await h.controller.runAutomaticTasks()
        let release = try #require(h.controller.availableUpdate)

        await h.controller.install(release, userInitiated: true)

        #expect(h.installer.calls == ["download 0.3.0", "prepare 0.3.0 from kept image", "install 0.3.0"])
        #expect(h.keptFiles.isEmpty)
        #expect(h.preferences.downloadedUpdate == nil)
        #expect(h.quits == 1)
    }

    @Test("a kept download that changed is downloaded afresh to install")
    func changedDownload() async throws {
        let h = Harness(checker: .latestRelease("v0.3.0"), mode: .download)
        await h.controller.runAutomaticTasks()
        try Data("changed".utf8).write(to: h.folder.appending(path: "AutoHush-0.3.0.dmg"))
        let release = try #require(h.controller.availableUpdate)

        await h.controller.install(release, userInitiated: true)

        #expect(h.installer.calls == ["download 0.3.0", "prepare 0.3.0", "install 0.3.0"])
    }

    @Test("a kept download that disappeared is downloaded again")
    func purgedDownload() async throws {
        let h = Harness(checker: .latestRelease("v0.3.0"), mode: .download)
        await h.controller.runAutomaticTasks()
        try FileManager.default.removeItem(at: h.folder.appending(path: "AutoHush-0.3.0.dmg"))

        await h.controller.runAutomaticTasks()

        #expect(h.downloads == 2)
        #expect(h.keptFiles == ["AutoHush-0.3.0.dmg"])
    }

    @Test("a newer release replaces the kept download")
    func newerReleaseReplacesDownload() async {
        let latest = Locked("v0.3.0")
        let h = Harness(checker: .latestRelease { latest.value }, mode: .download)
        await h.controller.runAutomaticTasks()
        latest.value = "v0.3.1"
        h.makeCheckDue()

        await h.controller.runAutomaticTasks()

        #expect(h.keptFiles == ["AutoHush-0.3.1.dmg"])
        #expect(h.preferences.downloadedUpdate?.version == "0.3.1")
        #expect(h.notifier.announced.map(\.key) == ["downloaded 0.3.0", "downloaded 0.3.1"])
    }

    @Test("a withdrawn release's download is deleted, with its notification")
    func withdrawnRelease() async {
        let latest = Locked("v0.3.0")
        let h = Harness(checker: .latestRelease { latest.value }, mode: .download)
        await h.controller.runAutomaticTasks()
        latest.value = "v0.2.0"
        h.makeCheckDue()

        await h.controller.runAutomaticTasks()

        #expect(h.keptFiles.isEmpty)
        #expect(h.preferences.downloadedUpdate == nil)
        #expect(h.notifier.withdrawals >= 1)
        #expect(h.offer == nil)
    }

    @Test("a download unused for a week is deleted and not downloaded again")
    func expiredDownload() async {
        let h = Harness(checker: .latestRelease("v0.3.0"), mode: .download)
        await h.controller.runAutomaticTasks()
        h.now = h.now.addingTimeInterval(UpdateDownloads.keepFor + 60)

        await h.controller.runAutomaticTasks()

        #expect(h.keptFiles.isEmpty)
        #expect(h.preferences.expiredUpdateVersion == "0.3.0")
        #expect(h.downloads == 1)
        #expect(h.offer?.state == .available) // still offered: installing downloads it
    }

    @Test("a failed download is tried again at the next run")
    func failedDownload() async {
        let installer = MockUpdateInstaller(downloadError: URLError(.notConnectedToInternet))
        let h = Harness(checker: .latestRelease("v0.3.0"), installer: installer, mode: .download)
        await h.controller.runAutomaticTasks()
        #expect(h.controller.status == "Couldn’t download version 0.3.0.")
        #expect(h.keptFiles.isEmpty)
        #expect(h.notifier.announced.isEmpty)

        installer.downloadError = nil
        await h.controller.runAutomaticTasks()
        #expect(h.keptFiles == ["AutoHush-0.3.0.dmg"])
        #expect(h.notifier.announced == [.downloaded(v030)])
    }

    @Test("choosing \"Notify me\", or turning checks off, deletes the download and its notification")
    func unwantedDownload() async {
        for turnOff in [{ (c: UpdateController) in c.mode = .notify }, { (c: UpdateController) in c.checksAutomatically = false }] {
            let h = Harness(checker: .latestRelease("v0.3.0"), mode: .download)
            await h.controller.runAutomaticTasks()
            turnOff(h.controller)
            #expect(h.keptFiles.isEmpty)
            #expect(h.preferences.downloadedUpdate == nil)
            #expect(h.notifier.withdrawals == 1)
            #expect(h.offer?.state == .available)
        }
    }

    @Test("choosing \"Install it automatically\" installs a kept download at the next quiet run")
    func downloadThenInstall() async {
        let h = Harness(checker: .latestRelease("v0.3.0"), mode: .download)
        await h.controller.runAutomaticTasks()
        h.controller.mode = .install
        #expect(h.keptFiles == ["AutoHush-0.3.0.dmg"])

        await h.controller.runAutomaticTasks()

        #expect(h.installer.calls == ["download 0.3.0", "prepare 0.3.0 from kept image", "install 0.3.0"])
        #expect(h.quits == 1)
    }

    @Test("where AutoHush can't update itself, downloading falls back to notifying")
    func cantInstallSoNotify() async {
        let h = Harness(checker: .latestRelease("v0.3.0"),
                        installer: MockUpdateInstaller(unavailability: .readOnlyLocation), mode: .download)
        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls.isEmpty)
        #expect(h.notifier.announced == [.available(v030, running: AppVersion("0.2.0")!)])
    }

    // MARK: - Notifications turned off

    @Test("with notifications off, the choice and the checks stay as they are, and the update is still offered",
          arguments: [AutomaticUpdates.notify, .download])
    func notificationsOffChangeNothing(mode: AutomaticUpdates) async {
        let h = Harness(checker: .latestRelease("v0.3.0"), mode: mode)
        h.notifier.currentPermission = .off
        await h.controller.runAutomaticTasks()

        #expect(h.controller.mode == mode)
        #expect(h.controller.checksAutomatically)
        #expect(h.settingsChanges == 0)
        #expect(h.offer?.release.version == v030) // the menu offers it; its icon shows it
    }

    @Test("a reset in System Settings is asked about again, once, and only after an answer")
    func notificationsResetAsksAgain() async {
        let h = Harness(checker: .offline, mode: .notify)
        h.notifier.currentPermission = .notAsked // the launch's question, not answered yet
        await h.controller.followNotificationPermission()
        #expect(h.notifier.permissionRequests == 0)

        h.notifier.currentPermission = .allowed
        await h.controller.followNotificationPermission()
        h.notifier.currentPermission = .notAsked // Reset Notifications…
        #expect(await h.controller.followNotificationPermission() == .notAsked)
        #expect(h.notifier.permissionRequests == 1)
        await h.controller.followNotificationPermission() // still waiting for the answer
        #expect(h.notifier.permissionRequests == 1)
        #expect(h.controller.mode == .notify)

        h.notifier.currentPermission = .off
        #expect(await h.controller.followNotificationPermission() == .off)
        #expect(h.controller.mode == .notify) // turned off, nothing changes
        h.notifier.currentPermission = .notAsked // reset again, while off
        await h.controller.runAutomaticTasks()
        #expect(h.notifier.permissionRequests == 2)
    }

    // MARK: - Install it automatically

    @Test("an automatic check installs a new version at a quiet moment, then quits so it opens")
    func installsAutomatically() async {
        let h = Harness(checker: .latestRelease("v0.3.0"))
        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls == ["prepare 0.3.0", "install 0.3.0"])
        #expect(h.quits == 1)
        #expect(h.statuses == ["Checking…", "Version 0.3.0 is available.", "Installing version 0.3.0…"])
        #expect(h.offer?.state == .installing)
        #expect(h.installer.lowDataModeAllowed == [false]) // like automatic downloads
        #expect(h.notifier.announced.isEmpty) // the new version says so
    }

    @Test("a release candidate found is only offered, never installed by itself, whatever was chosen (the user, 2026-10-29)")
    func releaseCandidateOnlyOffered() async {
        let h = Harness(checker: .releases([("v0.3.0-rc.1", true), ("v0.2.0", false)]))
        h.preferences.getsReleaseCandidates = true
        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls.isEmpty && h.quits == 0)
        #expect(h.notifier.announced == [.available(AppVersion("0.3.0-rc.1")!, running: AppVersion("0.2.0")!)])
        #expect(h.offer?.release.version == AppVersion("0.3.0-rc.1"))
    }

    @Test("a release candidate running without them is offered the latest release to go back to, never installed by itself")
    func backFromReleaseCandidateOnlyOffered() async {
        let h = Harness(checker: .latestRelease("v0.2.0"), currentVersion: AppVersion("0.3.0-rc.1"))
        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls.isEmpty && h.quits == 0)
        #expect(h.notifier.announced == [.available(AppVersion("0.2.0")!, running: AppVersion("0.3.0-rc.1")!)])
    }

    @Test("turning release candidates on is stored and checks at once, with automatic checks on")
    func turningReleaseCandidatesOn() async {
        let h = Harness(checker: .releases([("v0.3.0-rc.1", true), ("v0.2.0", false)]))
        h.controller.setGetsReleaseCandidates(true)
        #expect(h.preferences.getsReleaseCandidates)
        await TestWait.until { h.controller.availableUpdate != nil }
        #expect(h.controller.availableUpdate?.version == AppVersion("0.3.0-rc.1"))
        #expect(h.installer.calls.isEmpty)
    }

    @Test("while AutoHush is busy the update waits, and installs at the next quiet run")
    func waitsForQuietMoment() async {
        let h = Harness(checker: .latestRelease("v0.3.0"), quiet: Locked(false))
        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls.isEmpty)
        #expect(h.offer?.state == .available)

        h.quiet.value = true
        await h.controller.runAutomaticTasks() // no check due: installs what the last one found
        #expect(h.installer.calls == ["prepare 0.3.0", "install 0.3.0"])
        #expect(h.quits == 1)
    }

    @Test("an update that finds AutoHush busy once downloaded is discarded and stays offered")
    func busyAfterDownload() async {
        let quiet = Locked(true)
        let h = Harness(checker: .latestRelease("v0.3.0"),
                        installer: MockUpdateInstaller(onPrepare: { quiet.value = false }),
                        quiet: quiet)
        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls == ["prepare 0.3.0", "discard 0.3.0"])
        #expect(h.quits == 0)
        #expect(h.offer?.state == .available)
        #expect(h.controller.status == "Version 0.3.0 is available.")
    }

    @Test("nothing happens automatically with automatic checks off")
    func checksOff() async {
        let h = Harness(checker: .latestRelease("v0.3.0"))
        h.controller.checksAutomatically = false
        await h.controller.check(userInitiated: false)
        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls.isEmpty)
        #expect(h.notifier.announced.isEmpty)
        #expect(h.offer?.release.version == v030)
    }

    @Test("nothing is installed automatically without a disk image, or where AutoHush can't update itself")
    func notInstallable() async {
        let noImage = Harness(checker: .latestRelease("v0.3.0", diskImage: false))
        await noImage.controller.runAutomaticTasks()
        #expect(noImage.installer.calls.isEmpty)
        #expect(noImage.notifier.announced.map(\.key) == ["available 0.3.0"])

        let readOnly = Harness(checker: .latestRelease("v0.3.0"),
                               installer: MockUpdateInstaller(unavailability: .readOnlyLocation))
        await readOnly.controller.runAutomaticTasks()
        #expect(readOnly.installer.calls.isEmpty)
        #expect(readOnly.controller.installUnavailability == .readOnlyLocation)
        #expect(readOnly.offer?.release.version == v030)
    }

    @Test("a failed automatic install is reported once, stays offered, and isn't retried")
    func failedAutomaticInstall() async {
        let h = Harness(checker: .latestRelease("v0.3.0"), installer: MockUpdateInstaller(prepareError: UpdateInstallError.notGenuine))
        await h.controller.runAutomaticTasks()
        #expect(h.controller.status == "Couldn’t install version 0.3.0.")
        #expect(h.offer?.state == .available)
        #expect(h.quits == 0)
        #expect(h.notifier.announced == [.installFailed(v030)])

        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls == ["prepare 0.3.0"])
        #expect(h.notifier.announced.count == 1)
    }

    @Test("a kept download that fails to install is deleted")
    func failedKeptInstall() async {
        let installer = MockUpdateInstaller(prepareError: UpdateInstallError.notGenuine)
        let h = Harness(checker: .latestRelease("v0.3.0"), installer: installer, mode: .download)
        await h.controller.runAutomaticTasks()
        h.controller.mode = .install
        await h.controller.runAutomaticTasks()
        #expect(h.keptFiles.isEmpty)
        #expect(h.preferences.downloadedUpdate == nil)
    }

    @Test("an install the user asks for doesn't wait for a quiet moment")
    func userInstall() async throws {
        let h = Harness(checker: .latestRelease("v0.3.0"), quiet: Locked(false))
        await h.controller.check(userInitiated: false)
        let release = try #require(h.controller.availableUpdate)
        await h.controller.install(release, userInitiated: true)
        #expect(h.installer.calls == ["prepare 0.3.0", "install 0.3.0"])
        #expect(h.installer.lowDataModeAllowed == [true])
        #expect(h.quits == 1)
    }

    // MARK: - Launch and notifications

    @Test("after an update, the new version says so once, and clicking it opens the release page")
    func announcesUpdate() {
        let h = Harness(checker: .offline)
        h.preferences.lastLaunchedVersion = "0.1.0"
        h.controller.noteLaunch()
        h.controller.noteLaunch()
        #expect(h.notifier.isActive)
        #expect(h.notifier.announced == [.installed(AppVersion("0.2.0")!)])
        #expect(h.preferences.lastLaunchedVersion == "0.2.0")

        h.notifier.click(.installed, "0.2.0")
        #expect(h.opened == [URL(string: "https://github.com/hfustercabre/AutoHush/releases/tag/v0.2.0")!])
    }

    @Test("at launch, AutoHush asks for permission to notify, unless automatic checks are off")
    func asksForPermission() {
        let h = Harness(checker: .offline)
        h.controller.noteLaunch()
        #expect(h.notifier.permissionRequests == 1)

        let off = Harness(checker: .offline)
        off.controller.checksAutomatically = false
        off.controller.noteLaunch()
        #expect(off.notifier.permissionRequests == 0)
    }

    @Test("a first launch, or one with the same version, says nothing")
    func quietLaunch() {
        let h = Harness(checker: .offline)
        h.controller.noteLaunch()
        h.controller.noteLaunch()
        #expect(h.notifier.announced.isEmpty)
    }

    @Test("at launch, a kept download that isn't newer than the running version is deleted, and so is the mark of a version whose download expired")
    func manualUpdateDeletesDownload() throws {
        let h = Harness(checker: .offline, currentVersion: AppVersion("0.3.0"), mode: .download)
        try FileManager.default.createDirectory(at: h.folder, withIntermediateDirectories: true)
        let file = h.folder.appending(path: "AutoHush-0.3.0.dmg")
        try Data("0.3.0".utf8).write(to: file)
        h.preferences.downloadedUpdate = DownloadedUpdate(
            version: "0.3.0", sha256: try #require(UpdateInstaller.sha256(of: file)), downloadedAt: h.now
        )
        try Data("stray".utf8).write(to: h.folder.appending(path: "AutoHush-0.2.9.dmg"))

        h.controller.noteLaunch()

        #expect(h.keptFiles.isEmpty)
        #expect(h.preferences.downloadedUpdate == nil)

        // Its download expired, then the user installed it by hand: it may be downloaded again.
        h.preferences.expiredUpdateVersion = "0.3.0"
        h.controller.noteLaunch()
        #expect(h.preferences.expiredUpdateVersion == nil)
    }

    // MARK: - Alerts

    /// A check asked for that found 0.3.0, with its notes, at no quiet
    /// moment; its alert answered Later.
    private func updateOffered() async -> Harness {
        let h = Harness(checker: .latestRelease("v0.3.0", notes: "Fixes."), quiet: Locked(false))
        h.answer = .alertSecondButtonReturn
        await h.controller.check(userInitiated: true)
        return h
    }

    @Test("a check asked for offers the update with its notes; Later (Escape) leaves it in the menu")
    func offerChoices() async throws {
        let h = await updateOffered()
        let alert = try #require(h.alerts.first)
        #expect(alert.messageText == "AutoHush 0.3.0 Is Available")
        #expect(alert.buttons.map(\.title) == ["Download and Install", "Later", "Open Release Page"])
        #expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}", ""])
        #expect(alert.accessoryView is NSScrollView) // its notes, in a scrolling box
        #expect(h.offer?.state == .available)
    }

    @Test("an update offered again from the menu opens its release page with Open Release Page")
    func offerOpensReleasePage() async {
        let h = await updateOffered()
        h.answer = .alertThirdButtonReturn
        h.controller.presentAvailableUpdate() // the menu's "Install AutoHush 0.3.0…"
        #expect(h.opened == [URL(string: "https://github.com/hfustercabre/AutoHush/releases/tag/v0.3.0")!])
    }

    @Test("an update offered again from the menu installs at once with Download and Install (Return)")
    func offerInstallsAtOnce() async {
        let h = await updateOffered()
        h.answer = .alertFirstButtonReturn
        h.controller.presentAvailableUpdate() // the menu's "Install AutoHush 0.3.0…"
        await TestWait.until { h.quits == 1 }
        #expect(h.alerts.count == 2)
        #expect(h.installer.calls == ["prepare 0.3.0", "install 0.3.0"]) // not waiting for a quiet moment
    }

    @Test("an update's notes get a box as tall as they need, from 48 points for one line to 180, where long ones scroll")
    func offerNotesHeight() {
        let heights = ["Fixes.", String(repeating: "- A fix\n", count: 5), String(repeating: "- A fix\n", count: 40)]
            .map { UpdateController.notesView($0).frame.height }
        #expect(heights[0] == 48)
        #expect(heights[1] > 48 && heights[1] < 180)
        #expect(heights[2] == 180)
    }

    @Test("a check asked for by a click on a notification that no longer applies says what it found: up to date, no releases yet, or why it couldn't tell")
    func checkResults() async {
        let answering = { (status: Int, body: String) in
            UpdateChecker { (Data(body.utf8), HTTPURLResponse(url: $0.url!, statusCode: status, httpVersion: nil, headerFields: nil)!) }
        }
        let results: [(UpdateChecker, AppVersion?, title: String, message: String)] = [
            (.latestRelease("v0.2.0"), AppVersion("0.2.0"), "AutoHush Is Up to Date", "You have the latest version, 0.2.0."),
            (answering(404, ""), AppVersion("0.2.0"), "No Releases Yet", "No AutoHush release has been published on GitHub yet."),
            (.offline, AppVersion("0.2.0"), "Couldn’t Check for Updates", URLError(.notConnectedToInternet).localizedDescription),
            (answering(500, ""), AppVersion("0.2.0"), "Couldn’t Check for Updates", "GitHub answered with HTTP status 500."),
            (answering(200, #"{"tag_name": "latest"}"#), AppVersion("0.2.0"), "Couldn’t Check for Updates",
             "GitHub’s release information couldn’t be read."),
            (.offline, nil, "Couldn’t Check for Updates", "AutoHush’s version is unknown."),
        ]
        // Notifications about an update available, downloaded or that failed to install, in turn.
        let clicked: [UpdateNotice.Kind] = [.available, .downloaded, .installFailed]
        for (index, (checker, version, title, message)) in results.enumerated() {
            let h = Harness(checker: checker, currentVersion: version)
            h.notifier.click(clicked[index % clicked.count], "0.3.0") // nothing offered: it checks
            await TestWait.until { !h.alerts.isEmpty }
            #expect(h.alerts.map(\.messageText) == [title])
            #expect(h.alerts.first?.informativeText == message)
            #expect(h.menuClosings == 1) // the menu, open while it checked, closes first
        }
    }

    @Test("an install asked for that fails says why: Open Release Page (Return) opens the release to install it by hand, Later (Escape) closes it")
    func installError() async throws {
        let answers: [(NSApplication.ModalResponse, opensPage: Bool)] = [(.alertFirstButtonReturn, true), (.alertSecondButtonReturn, false)]
        for (answer, opensPage) in answers {
            let h = Harness(checker: .latestRelease("v0.3.0"), installer: MockUpdateInstaller(prepareError: UpdateInstallError.notGenuine))
            await h.controller.check(userInitiated: false)
            let release = try #require(h.controller.availableUpdate)
            h.answer = answer
            await h.controller.install(release, userInitiated: true)
            let alert = try #require(h.alerts.first)
            #expect(alert.messageText == "Couldn’t Install the Update")
            #expect(alert.informativeText == UpdateInstallError.notGenuine.localizedDescription)
            #expect(alert.buttons.map(\.title) == ["Open Release Page", "Later"])
            #expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}"])
            #expect(h.opened == (opensPage ? [release.pageURL] : []))
            #expect(h.notifier.announced.isEmpty) // said in the alert, not in a notification
        }
    }

    // MARK: - Scheduling

    @Test("the automatic work runs 30 s after launch, then hourly, on one timer at a time; checks are due daily, and never when turned off")
    func checkDue() async throws {
        let h = Harness(checker: .offline)
        h.controller.scheduleAutomaticChecks()
        let first = try #require(h.controller.timer)
        h.controller.scheduleAutomaticChecks()
        let timer = try #require(h.controller.timer)
        defer { timer.invalidate() }
        #expect(!first.isValid)
        #expect(timer.isValid && timer.timeInterval == 60 * 60)
        #expect(abs(timer.fireDate.timeIntervalSinceNow - 30) < 5)
        timer.fire() // its run: a check is due
        await TestWait.until { h.controller.status == "Couldn’t check for updates." }
        #expect(h.statuses == ["Checking…", "Couldn’t check for updates."])

        let now = Date()
        #expect(h.controller.isCheckDue(now: now))
        h.preferences.lastUpdateCheck = now.addingTimeInterval(-3600)
        #expect(!h.controller.isCheckDue(now: now))
        h.preferences.lastUpdateCheck = now.addingTimeInterval(-25 * 3600)
        #expect(h.controller.isCheckDue(now: now))
        h.controller.checksAutomatically = false
        #expect(!h.controller.isCheckDue(now: now))
    }
}
