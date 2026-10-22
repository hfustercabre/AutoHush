import Foundation
@testable import AutoHushApp
import AutoHushTestSupport
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

/// What Add an App's stand-ins saw and answer (the apps on the Mac, the
/// check's helper, the rest of AutoHush and the feature's windows), for the
/// model's tests and its windows'.
@MainActor
final class World {
    var apps = [CheckableApp(bundleID: "com.example.player", name: "Player", url: URL(filePath: "/Applications/Player.app"), nowPlaying: true),
                CheckableApp(bundleID: "com.example.other", name: "Other", url: URL(filePath: "/Applications/Other.app"))]
    var traits = CheckedAppTraits(scriptable: false, framework: nil, needsLaunchOption: false)
    var running = true
    /// Whether opening the app, reopening it and starting a check go.
    var opens = true
    var reopens = true
    var startsCheck = true
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
    var macCanMute = true
    /// How many times the model asked whether the Mac can mute (Core Audio, live).
    var macCanMuteReads = 0
    var taps: [Bool] = []
    var audioRequests = 0
    var menuBarSettingsOpened = 0
    var hasLog = false
    var logsShown = 0
    var autoHushReopened = 0
    /// Each time AutoHush's player was held for a check (`true`), and let go.
    var holds: [Bool] = []
    /// Holds the model's polls until the test ends them.
    var heldSleep: ManualSleep?
    var exists = true
    var run = FakeCheckRun()
    var runs = 0
    /// The running check's report, for lines after its first.
    var report: (@MainActor @Sendable (String) -> Void)?
    /// Kept checks, in a suite of their own, removed with the world.
    private let keptSuite = TestDefaults("AddAppModelTests")
    lazy var kept = KeptCheckStore(defaults: keptSuite.defaults)

    deinit {
        keptSuite.remove()
    }
}

extension AddAppModel {
    /// A model on `world`'s stand-ins, as `AddAppFeature` makes one on AutoHush's.
    convenience init(_ world: World) {
        // The model's polls a moment apart, not spinning on the main actor,
        // which every main-actor test shares; or held, when a test ends them
        // itself.
        self.init(reader: world, helper: world, host: world, presenter: world, keptChecks: world.kept, now: { world.now },
                  sleep: { duration in
                      if let held = world.heldSleep { await held.sleep(duration) } else { try? await Task.sleep(for: .milliseconds(5)) }
                  })
    }
}

/// The apps on the Mac.
extension World: AppReading {
    func listApps() async -> [CheckableApp] { apps }

    func app(at url: URL) -> Result<CheckableApp, OtherAppProblem> {
        url.lastPathComponent == "AutoHush.app" ? .failure(.autoHush)
            : .success(CheckableApp(bundleID: "com.example.picked", name: "Picked", url: url))
    }

    func traits(ofAppAt url: URL) -> CheckedAppTraits { traits }
    func isRunning(_ bundleID: String) -> Bool { running }
    func appExists(at url: URL) -> Bool { exists }

    func open(_ app: CheckableApp, withLaunchOption: Bool) async -> Bool {
        opened.append((app.bundleID, withLaunchOption))
        guard opens else { return false }
        running = true
        return true
    }

    func isPlaying(_ app: CheckableApp, traits: CheckedAppTraits) async -> Bool { playing }
}

/// The check's helper.
extension World: CheckHelping {
    func runsWithLaunchOption(_ app: CheckableApp) async -> Bool? { runsWithOption }

    func reopenWithLaunchOption(_ app: CheckableApp) async -> Bool {
        reopened += 1
        return reopens
    }

    func startCheck(_ app: CheckableApp, taps: Bool, onLine: @escaping @MainActor @Sendable (String) -> Void) -> any CheckRunning? {
        guard startsCheck else { return nil }
        self.taps.append(taps)
        runs += 1
        report = onLine
        onLine("Press Test")
        return run
    }
}

/// The rest of AutoHush.
extension World: AddAppHost {
    var supportedApps: [PlayerOption] { [] }
    var isAntiDot: Bool { antiDot }
    func turnOffAntiDot() { antiDot = false }

    func checkPermissions(_ app: CheckableApp, scriptable: Bool) async -> CheckPermissions {
        var permissions = self.permissions
        if scriptable, permissions.automation == nil { permissions.automation = .notAsked }
        return permissions
    }

    func requestCheckPermission(_ permission: CheckPermission, app: CheckableApp, current: CheckPermissions) async {
        guard permission == .audioRecording else { return }
        audioRequests += 1
        // Turned down: System Settings opens, and AutoHush waits to reopen.
        if permissions.audio == .denied { permissions.audio = .needsReopen }
    }

    func holdsPlayerForCheck(_ held: Bool) { holds.append(held) }
    func reopenForAudioRecording() { autoHushReopened += 1 }
    func reopenKeepingAddApp() { autoHushReopened += 1 }

    func useCheckedApp(_ result: CheckResult, asksToReopen: Bool) {
        used.append(result)
        self.asksToReopen.append(asksToReopen)
    }
}

/// The feature's windows, the check's panel and its log.
extension World: AddAppPresenting {
    func showChooser() { choosers += 1 }
    func closeChooser() {}
    func showWarning() { warnings += 1 }
    func closeWarning() { warningsClosed += 1 }
    func checkStarted(_ app: CheckableApp) { panel.append("shown") }
    func checkEnded() { panel.append("hidden") }

    var canMuteOutput: Bool {
        macCanMuteReads += 1
        return macCanMute
    }

    var hasCheckLog: Bool { hasLog }
    func showCheckLog() { logsShown += 1 }
    func openMenuBarSettings() { menuBarSettingsOpened += 1 }
    func closeWindow() { closed += 1 }
}
