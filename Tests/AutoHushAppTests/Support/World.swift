import Foundation
@testable import AutoHushApp
import CheckedPlayers

/// A check that ends when the test says.
@MainActor
final class FakeCheckRun: CheckRunning {
    var stopped = false
    /// Stopped, it ends at once; else it puts things back first, until `finish`.
    var endsWhenStopped = true
    private var end: PlayerCheckEnd?
    private var waiting: [CheckedContinuation<PlayerCheckEnd, Never>] = []

    func stop() {
        stopped = true
        if endsWhenStopped { finish(.stopped) }
    }

    func finish(_ end: PlayerCheckEnd) {
        self.end = end
        waiting.forEach { $0.resume(returning: end) }
        waiting = []
    }

    func waitForEnd() async -> PlayerCheckEnd {
        if let end { return end }
        return await withCheckedContinuation { waiting.append($0) }
    }
}

/// What Add an App's fake services saw and answer, for the model's tests
/// and its windows'.
@MainActor
final class World {
    var apps = [CheckableApp(bundleID: "com.example.player", name: "Player", url: URL(filePath: "/Applications/Player.app"), nowPlaying: true),
                CheckableApp(bundleID: "com.example.other", name: "Other", url: URL(filePath: "/Applications/Other.app"))]
    var traits = CheckedAppTraits(scriptable: false, framework: nil, needsLaunchOption: false)
    var running = true
    var runsWithOption: Bool?
    var permissions = CheckPermissions(accessibility: true, audio: .allowed)
    var playing = false
    var now = Date(timeIntervalSince1970: 1000)
    var opened: [(String, Bool)] = []
    var reopened = 0
    var warnings = 0
    var used: [CheckResult] = []
    var asksToReopen: [Bool] = []
    var closed = 0
    var choosers = 0
    var warningsClosed = 0
    var panel: [String] = []
    var antiDot = false
    var taps: [Bool] = []
    var audioRequests = 0
    var exists = true
    var run = FakeCheckRun()
    var runs = 0
    /// The running check's report, for lines after its first.
    var report: (@MainActor @Sendable (String) -> Void)?
    let kept = KeptCheckStore(defaults: UserDefaults(suiteName: "AddAppModelTests-\(UUID().uuidString)")!)

    var services: AddAppServices {
        AddAppServices(
            listApps: { self.apps },
            appAt: { url in
                url.lastPathComponent == "AutoHush.app" ? .failure(.autoHush)
                    : .success(CheckableApp(bundleID: "com.example.picked", name: "Picked", url: url))
            },
            showChooser: { self.choosers += 1 },
            traits: { _ in self.traits },
            isRunning: { _ in self.running },
            exists: { _ in self.exists },
            open: { app, option in
                self.opened.append((app.bundleID, option))
                self.running = true
                return true
            },
            runsWithLaunchOption: { _ in self.runsWithOption },
            reopen: { _ in
                self.reopened += 1
                return true
            },
            permissions: { _, scriptable in
                var permissions = self.permissions
                if scriptable, permissions.automation == nil { permissions.automation = .notAsked }
                return permissions
            },
            request: { permission, _, _ in if permission == .audioRecording { self.audioRequests += 1 } },
            antiDot: { self.antiDot },
            isPlaying: { _, _ in self.playing },
            startCheck: { _, taps, onLine in
                self.taps.append(taps)
                self.runs += 1
                self.report = onLine
                onLine("Press Test")
                return self.run
            },
            showWarning: { self.warnings += 1 },
            closeWarning: { self.warningsClosed += 1 },
            checkStarted: { _ in self.panel.append("shown") },
            checkEnded: { self.panel.append("hidden") },
            keptChecks: kept,
            use: { result, asks in
                self.used.append(result)
                self.asksToReopen.append(asks)
            },
            close: { self.closed += 1 },
            now: { self.now },
            sleep: { _ in await Task.yield() }
        )
    }
}
