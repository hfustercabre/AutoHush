import AppKit
import Foundation
import Observation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

extension UpdateControllerTests {
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
