import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushPlayers
import SpotifySupport
import AutoHushTestSupport

@Suite("UpdateController")
@MainActor
struct UpdateControllerTests {
    /// Records what the controller reports, and keeps its preferences, its
    /// downloads folder and its clock.
    @MainActor
    private final class Harness {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let installer: MockUpdateInstaller
        let notifier = MockUpdateNotifier()
        /// Whether AutoHush could restart unnoticed right now.
        let quiet: Flag
        let folder = FileManager.default.temporaryDirectory.appending(path: "UpdateControllerTests-\(UUID().uuidString)")
        var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var offers: [UpdateOffer?] = []
        var statuses: [String] = []
        var opened: [URL] = []
        var quits = 0
        private(set) var controller: UpdateController!

        init(
            checker: UpdateChecker,
            installer: MockUpdateInstaller = MockUpdateInstaller(),
            quiet: Flag = Flag(true),
            currentVersion: AppVersion? = AppVersion("0.2.0"),
            mode: AutomaticUpdates = .install
        ) {
            self.installer = installer
            self.quiet = quiet
            preferences.automaticUpdates = mode
            controller = UpdateController(
                checker: checker,
                installer: installer,
                notifier: notifier,
                preferences: preferences,
                downloadsFolder: folder,
                currentVersion: currentVersion,
                now: { [unowned self] in now },
                isQuietMoment: { quiet.value },
                quit: { [unowned self] in quits += 1 },
                openURL: { [unowned self] in opened.append($0) },
                onOffer: { [unowned self] in offers.append($0) },
                onStatus: { [unowned self] in statuses.append($0) }
            )
        }

        deinit {
            try? FileManager.default.removeItem(at: folder)
        }

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

    private actor FetchCount {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    private let v030 = AppVersion("0.3.0")!

    // MARK: - Checking

    @Test("a check asked for while one is under way doesn't start another")
    func overlappingChecks() async {
        let fetches = FetchCount()
        let h = Harness(checker: .latestRelease({ "v0.2.0" }, onFetch: {
            await fetches.increment()
            try? await Task.sleep(for: .milliseconds(50)) // still under way when the second check is asked for
        }))

        async let first: Void = h.controller.check(userInitiated: false)
        async let second: Void = h.controller.check(userInitiated: false)
        _ = await (first, second)

        #expect(await fetches.value == 1)
        #expect(h.statuses == ["Checking…", "AutoHush 0.2.0 is up to date."])
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
        let latest = LatestTag("v0.3.0")
        let h = Harness(checker: .latestRelease { latest.value }, mode: .notify)
        await h.controller.runAutomaticTasks()
        #expect(h.offer != nil)
        #expect(h.notifier.announced == [.available(v030, running: AppVersion("0.2.0")!)])

        latest.value = "v0.2.0" // the newer release was withdrawn
        await h.controller.check(userInitiated: false)
        #expect(h.controller.availableUpdate == nil)
        #expect(h.offers.last == .some(nil))
        #expect(h.notifier.withdrawals == 1)
        #expect(h.statuses.last == "AutoHush 0.2.0 is up to date.")
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
        #expect(h.statuses.last == "Couldn't check for updates.")
        #expect(h.preferences.lastUpdateCheck == nil)
        #expect(h.offers.isEmpty)
    }

    @Test("without a known app version nothing is asked")
    func unknownVersion() async {
        let h = Harness(checker: .offline, currentVersion: nil)
        await h.controller.check(userInitiated: false)
        #expect(h.statuses == ["The app's version is unknown."])
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
        let latest = LatestTag("v0.3.0")
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
        let latest = LatestTag("v0.3.0")
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
        let latest = LatestTag("v0.3.0")
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
        #expect(h.statuses.last == "Couldn't download version 0.3.0.")
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

    @Test("while AutoHush is busy the update waits, and installs at the next quiet run")
    func waitsForQuietMoment() async {
        let h = Harness(checker: .latestRelease("v0.3.0"), quiet: Flag(false))
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
        let quiet = Flag(true)
        let h = Harness(checker: .latestRelease("v0.3.0"),
                        installer: MockUpdateInstaller(onPrepare: { quiet.value = false }),
                        quiet: quiet)
        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls == ["prepare 0.3.0", "discard 0.3.0"])
        #expect(h.quits == 0)
        #expect(h.offer?.state == .available)
        #expect(h.statuses.last == "Version 0.3.0 is available.")
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
        #expect(h.statuses.last == "Couldn't install version 0.3.0.")
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
        let h = Harness(checker: .latestRelease("v0.3.0"), quiet: Flag(false))
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

    @Test("a first launch, or one with the same version, says nothing")
    func quietLaunch() {
        let h = Harness(checker: .offline)
        h.controller.noteLaunch()
        h.controller.noteLaunch()
        #expect(h.notifier.announced.isEmpty)
    }

    @Test("at launch, a kept download that isn't newer than the running version is deleted")
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
    }

    // MARK: - Scheduling

    @Test("automatic checks are due daily, and never when turned off")
    func checkDue() {
        let h = Harness(checker: .offline)
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

/// A switch the tests flip while the controller runs.
private final class Flag: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

/// The tag the fake GitHub answers with; changeable between checks.
private final class LatestTag: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
}
