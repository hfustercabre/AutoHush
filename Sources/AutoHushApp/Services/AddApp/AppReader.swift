import AppKit
import AutoHushKit
import AutoHushPlayers
import CheckedPlayers

/// The apps on the Mac, read live for Add an App: listed and opened with
/// the check's helper, the players AutoHush supports left out (its host's),
/// heard as the check hears them.
@MainActor
struct AppReader: AppReading {
    /// AutoHush's own playercheck; `nil` when it's missing from the app.
    let helper: PlayerCheckHelper?
    /// The players AutoHush supports, and whether AntiDot mode is on.
    weak var host: any AddAppHost?

    func listApps() async -> [CheckableApp] {
        // The supported players aren't offered (their support is AutoHush's
        // own), nor Apple's apps that are no players.
        let supported = Set((host?.supportedApps ?? []).map(\.bundleID))
        return await CheckableApps.find(helper: helper, excluding: supported.union(SupportedPlayers.notPlayers))
    }

    func app(at url: URL) -> Result<CheckableApp, OtherAppProblem> {
        Self.checkableApp(at: url, supported: host?.supportedApps ?? [])
    }

    func traits(ofAppAt url: URL) -> CheckedAppTraits {
        CheckedAppTraits.of(appAt: url)
    }

    func isRunning(_ bundleID: String) -> Bool {
        NSRunningApplication.running(bundleID) != nil
    }

    func appExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func open(_ app: CheckableApp, withLaunchOption: Bool) async -> Bool {
        if withLaunchOption, let helper { return await helper.reopenWithLaunchOption(app.url) }
        return await Self.openInBackground(app)
    }

    func isPlaying(_ app: CheckableApp, traits: CheckedAppTraits) async -> Bool {
        // A browser's web app plays through its browser.
        let source = if case .browserWebApp(let browser)? = traits.framework { browser } else { app.bundleID }
        guard let pid = NSRunningApplication.running(source)?.processIdentifier else { return false }
        // AntiDot mode taps no sound: its level isn't measured.
        let antiDot = host?.isAntiDot ?? true
        var playing = AppPlaying()
        if antiDot { playing.levelMeasured = { false } }
        return await playing.plays(pid)
    }

    func hasWindowWithinReach(_ app: CheckableApp) async -> Bool {
        guard let pid = NSRunningApplication.running(app.bundleID)?.processIdentifier else { return false }
        return await Self.windowWithinReach(pid)
    }

    /// Off the main actor: a look at the windows on other desktops takes
    /// about 70 ms, up to 1 s.
    @concurrent
    private nonisolated static func windowWithinReach(_ pid: pid_t) async -> Bool {
        NSRunningApplication(processIdentifier: pid).map(AppWindows.hasWindowWithinReach) ?? false
    }

    /// An app picked on the disk (Other App…), named as the list names it,
    /// unless AutoHush supports it already (`supported`) or it's AutoHush.
    static func checkableApp(at url: URL, supported: [PlayerOption]) -> Result<CheckableApp, OtherAppProblem> {
        guard let app = CheckableApp.at(url) else { return .failure(.notAnApp) }
        if app.bundleID == Bundle.main.bundleIdentifier || app.bundleID.hasPrefix("com.autohush.") { return .failure(.autoHush) }
        if let player = supported.first(where: { $0.bundleID == app.bundleID }) { return .failure(.supported(player.name)) }
        return .success(app)
    }

    /// Opens the app without bringing it forward, and waits (up to 10 s)
    /// for it to run.
    static func openInBackground(_ app: CheckableApp) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        guard (try? await NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)) != nil else { return false }
        for _ in 0..<20 where NSRunningApplication.running(app.bundleID) == nil {
            try? await Task.sleep(for: .milliseconds(500))
        }
        return NSRunningApplication.running(app.bundleID) != nil
    }
}
