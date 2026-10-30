import AppKit
import Foundation
import Observation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

extension UpdateControllerTests {
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
}
