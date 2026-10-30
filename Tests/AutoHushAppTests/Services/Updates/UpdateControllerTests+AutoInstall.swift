import AppKit
import Foundation
import Observation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

extension UpdateControllerTests {
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

    @Test("turning release candidates off withdraws one offered at once, its notification too, with no check")
    func turningReleaseCandidatesOff() async {
        let requests = Locked(0)
        let h = Harness(checker: .releases([("v0.3.0-rc.1", true), ("v0.2.0", false)], onRequest: { _ in requests.value += 1 }),
                        mode: .notify)
        h.preferences.getsReleaseCandidates = true
        await h.controller.runAutomaticTasks()
        #expect(h.offer?.release.version == AppVersion("0.3.0-rc.1"))
        #expect(h.notifier.announced.count == 1)

        h.controller.setGetsReleaseCandidates(false)
        #expect(!h.preferences.getsReleaseCandidates)
        #expect(h.controller.availableUpdate == nil && h.offer == nil)
        #expect(h.notifier.withdrawals == 1)
        #expect(h.controller.status == nil) // Settings says when the last check was
        #expect(h.controller.checking == nil && requests.value == 1)
    }

    @Test("a check under way as release candidates are turned off asks again without them: none is offered")
    func releaseCandidatesOffDuringCheck() async {
        let gate = Gate()
        let h = Harness(checker: Self.heldCandidate(at: gate, latest: "v0.2.1"))
        h.preferences.getsReleaseCandidates = true
        let checking = Task { await h.controller.check(userInitiated: true) }
        await TestWait.until { await gate.waiting == 1 } // asked with release candidates
        h.controller.setGetsReleaseCandidates(false)
        await gate.open()
        await checking.value
        #expect(h.controller.availableUpdate?.version == AppVersion("0.2.1"))
        #expect(h.offers.allSatisfy { $0?.release.version.isReleaseCandidate != true })
        #expect(h.alerts.map(\.messageText).allSatisfy { !$0.contains("RC") })
    }

    /// GitHub with a release candidate, its list held at `gate`, newer than
    /// the `latest` release.
    private static func heldCandidate(at gate: Gate, latest: String) -> UpdateChecker {
        UpdateChecker { request in
            let page = "https://github.com/\(ProjectInfo.repository)/releases/tag/"
            let body: String
            if request.url?.path().hasSuffix("/releases") == true {
                await gate.wait()
                body = #"[{"tag_name": "v0.3.0-rc.1", "prerelease": true, "html_url": "\#(page)v0.3.0-rc.1", "assets": []}]"#
            } else {
                body = #"{"tag_name": "\#(latest)", "html_url": "\#(page)\#(latest)", "assets": []}"#
            }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
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
}
