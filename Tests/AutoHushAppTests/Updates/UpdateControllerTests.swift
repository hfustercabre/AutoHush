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
    /// Records what the controller reports, and keeps its preferences.
    @MainActor
    private final class Harness {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let installer: MockUpdateInstaller
        /// Whether AutoHush could restart unnoticed right now.
        let quiet: Flag
        var offered: [AppRelease?] = []
        var statuses: [String] = []
        var quits = 0
        private(set) var controller: UpdateController!

        init(
            checker: UpdateChecker,
            installer: MockUpdateInstaller = MockUpdateInstaller(),
            quiet: Flag = Flag(true),
            currentVersion: AppVersion? = AppVersion("0.2.0")
        ) {
            self.installer = installer
            self.quiet = quiet
            controller = UpdateController(
                checker: checker,
                installer: installer,
                preferences: preferences,
                currentVersion: currentVersion,
                isQuietMoment: { quiet.value },
                quit: { [unowned self] in quits += 1 },
                onAvailableUpdate: { [unowned self] in offered.append($0) },
                onStatus: { [unowned self] in statuses.append($0) }
            )
        }
    }

    private actor FetchCount {
        private(set) var value = 0
        func increment() { value += 1 }
    }

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
        #expect(h.controller.availableUpdate?.version == AppVersion("0.3.0"))
        #expect(h.offered.last??.version == AppVersion("0.3.0"))
        #expect(h.statuses == ["Checking…", "Version 0.3.0 is available."])
        #expect(h.preferences.lastUpdateCheck != nil)
    }

    @Test("an up-to-date check clears an earlier offer")
    func upToDate() async {
        let latest = LatestTag("v0.3.0")
        let h = Harness(checker: .latestRelease { latest.value })
        await h.controller.check(userInitiated: false)
        #expect(h.controller.availableUpdate != nil)

        latest.value = "v0.2.0" // the newer release was withdrawn
        await h.controller.check(userInitiated: false)
        #expect(h.controller.availableUpdate == nil)
        #expect(h.offered.last == .some(nil))
        #expect(h.statuses.last == "AutoHush 0.2.0 is up to date.")
    }

    @Test("a failed automatic check is quiet and doesn't count as a check")
    func failedCheck() async {
        let h = Harness(checker: .offline)
        await h.controller.check(userInitiated: false)
        #expect(h.statuses.last == "Couldn't check for updates.")
        #expect(h.preferences.lastUpdateCheck == nil)
        #expect(h.offered.isEmpty)
    }

    @Test("without a known app version nothing is asked")
    func unknownVersion() async {
        let h = Harness(checker: .offline, currentVersion: nil)
        await h.controller.check(userInitiated: false)
        #expect(h.statuses == ["The app's version is unknown."])
    }

    // MARK: - Installing

    @Test("an automatic check installs a new version at a quiet moment, then quits so it opens")
    func installsAutomatically() async {
        let h = Harness(checker: .latestRelease("v0.3.0"))
        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls == ["prepare 0.3.0", "install 0.3.0"])
        #expect(h.quits == 1)
        #expect(h.statuses == ["Checking…", "Version 0.3.0 is available.", "Installing version 0.3.0…"])
        #expect(h.offered.last == .some(nil)) // not offered in the menu while installing
    }

    @Test("while AutoHush is busy the update waits, and installs at the next quiet run")
    func waitsForQuietMoment() async {
        let h = Harness(checker: .latestRelease("v0.3.0"), quiet: Flag(false))
        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls.isEmpty)
        #expect(h.offered.last??.version == AppVersion("0.3.0"))

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
        #expect(h.offered.last??.version == AppVersion("0.3.0"))
        #expect(h.statuses.last == "Version 0.3.0 is available.")
    }

    @Test("automatic installs need automatic checks and installs on", arguments: [(false, true), (true, false)])
    func automaticInstallSwitches(checks: Bool, installs: Bool) async {
        let h = Harness(checker: .latestRelease("v0.3.0"))
        h.controller.checksAutomatically = checks
        h.controller.installsAutomatically = installs
        await h.controller.check(userInitiated: false)
        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls.isEmpty)
        #expect(h.offered.last??.version == AppVersion("0.3.0"))
    }

    @Test("nothing is installed automatically without a disk image, or where AutoHush can't update itself")
    func notInstallable() async {
        let noImage = Harness(checker: .latestRelease("v0.3.0", diskImage: false))
        await noImage.controller.runAutomaticTasks()
        #expect(noImage.installer.calls.isEmpty)

        let readOnly = Harness(checker: .latestRelease("v0.3.0"),
                               installer: MockUpdateInstaller(unavailability: .readOnlyLocation))
        await readOnly.controller.runAutomaticTasks()
        #expect(readOnly.installer.calls.isEmpty)
        #expect(readOnly.controller.installUnavailability == .readOnlyLocation)
        #expect(readOnly.offered.last??.version == AppVersion("0.3.0"))
    }

    @Test("a failed automatic install is reported in Settings, stays offered, and isn't retried")
    func failedAutomaticInstall() async {
        let h = Harness(checker: .latestRelease("v0.3.0"), installer: MockUpdateInstaller(prepareError: UpdateInstallError.notGenuine))
        await h.controller.runAutomaticTasks()
        #expect(h.statuses.last == "Couldn't install version 0.3.0.")
        #expect(h.offered.last??.version == AppVersion("0.3.0"))
        #expect(h.quits == 0)

        await h.controller.runAutomaticTasks()
        #expect(h.installer.calls == ["prepare 0.3.0"])
    }

    @Test("an install the user asks for doesn't wait for a quiet moment")
    func userInstall() async throws {
        let h = Harness(checker: .latestRelease("v0.3.0"), quiet: Flag(false))
        await h.controller.check(userInitiated: false)
        let release = try #require(h.controller.availableUpdate)
        await h.controller.install(release, userInitiated: true)
        #expect(h.installer.calls == ["prepare 0.3.0", "install 0.3.0"])
        #expect(h.quits == 1)
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

