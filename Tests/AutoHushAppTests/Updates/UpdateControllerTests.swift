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
        var offered: [AppRelease?] = []
        var statuses: [String] = []
        private(set) var controller: UpdateController!

        init(checker: UpdateChecker, currentVersion: AppVersion? = AppVersion("0.2.0")) {
            controller = UpdateController(
                checker: checker,
                preferences: preferences,
                currentVersion: currentVersion,
                onAvailableUpdate: { [unowned self] in offered.append($0) },
                onStatus: { [unowned self] in statuses.append($0) }
            )
        }
    }

    private static func releaseChecker(_ tag: String) -> UpdateChecker {
        UpdateChecker { request in
            let body = #"{"tag_name": "\#(tag)", "html_url": "https://github.com/hfustercabre/AutoHush/releases/tag/\#(tag)"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    private static let offline = UpdateChecker { _ in throw URLError(.notConnectedToInternet) }

    private actor FetchCount {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    @Test("a check asked for while one is under way doesn't start another")
    func overlappingChecks() async {
        let fetches = FetchCount()
        let h = Harness(checker: UpdateChecker { request in
            await fetches.increment()
            try? await Task.sleep(for: .milliseconds(50)) // still under way when the second check is asked for
            let body = #"{"tag_name": "v0.2.0", "html_url": "https://github.com/hfustercabre/AutoHush/releases/tag/v0.2.0"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })

        async let first: Void = h.controller.check(userInitiated: false)
        async let second: Void = h.controller.check(userInitiated: false)
        _ = await (first, second)

        #expect(await fetches.value == 1)
        #expect(h.statuses == ["Checking…", "AutoHush 0.2.0 is up to date."])
    }

    @Test("a check that finds a newer release offers it and remembers when it ran")
    func updateAvailable() async {
        let h = Harness(checker: Self.releaseChecker("v0.3.0"))
        await h.controller.check(userInitiated: false)
        #expect(h.controller.availableUpdate?.version == AppVersion("0.3.0"))
        #expect(h.offered.last??.version == AppVersion("0.3.0"))
        #expect(h.statuses == ["Checking…", "Version 0.3.0 is available."])
        #expect(h.preferences.lastUpdateCheck != nil)
    }

    @Test("an up-to-date check clears an earlier offer")
    func upToDate() async {
        let latest = LatestTag("v0.3.0")
        let h = Harness(checker: UpdateChecker { request in
            let tag = latest.value
            let body = #"{"tag_name": "\#(tag)", "html_url": "https://github.com/hfustercabre/AutoHush/releases/tag/\#(tag)"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
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
        let h = Harness(checker: Self.offline)
        await h.controller.check(userInitiated: false)
        #expect(h.statuses.last == "Couldn't check for updates.")
        #expect(h.preferences.lastUpdateCheck == nil)
        #expect(h.offered.isEmpty)
    }

    @Test("without a known app version nothing is asked")
    func unknownVersion() async {
        let h = Harness(checker: Self.offline, currentVersion: nil)
        await h.controller.check(userInitiated: false)
        #expect(h.statuses == ["The app's version is unknown."])
    }

    @Test("automatic checks are due daily, and never when turned off")
    func checkDue() {
        let h = Harness(checker: Self.offline)
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

/// The tag the fake GitHub answers with; changeable between checks.
private final class LatestTag: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
}

