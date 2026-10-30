import AppKit
import AutoHushKit
import CheckPanel
import CheckedPlayers
import PlayerCheckKit
import SwiftUI

@MainActor @Observable
final class Checker {
    var apps: [InstalledApp] = []
    var isScanning = false
    var runningIDs: Set<String> = []
    /// What's shown per app: its check running, else its last finished one
    /// (else a check that stopped or failed).
    var reports: [InstalledApp.ID: CheckReport] = [:]
    /// The last finished check per app, kept between launches: a check
    /// stopped or failed leaves it in place.
    var finished: [InstalledApp.ID: CheckReport] = [:]
    /// Why the last check of an app didn't finish, while its last finished
    /// check is shown instead.
    var attemptNotes: [InstalledApp.ID: String] = [:]
    /// A check cancelled before it did anything, as a permission it needs
    /// isn't allowed (`CheckExitStatus.permissionMissing`): what it said, and
    /// the first permission missing, for its pane in System Settings.
    var permissionProblems: [InstalledApp.ID: (text: String, missing: CheckReportLine.Permission?)] = [:]
    var checkingID: InstalledApp.ID?
    /// The check running, to tell it from one started after it was stopped.
    var attempt: UUID?
    var isTrusted = AXIsProcessTrusted()
    /// macOS's own Now Playing list, by bundle ID; why it couldn't be read.
    var clients: [String: NowPlayingListLine] = [:]
    var clientsProblem: String?
    var isReadingClients = false
    /// When the list was last read: the next read asks only for what changed
    /// since (the first reads macOS's log since the Mac started).
    var clientsReadAt: Date?
    /// A read asked for while another ran (true: a full one), done after it.
    var readAgain: Bool?
    /// The last Play or Pause per app: what playercheck said, and whether it
    /// worked (nil while it runs).
    var controls: [InstalledApp.ID: (text: String, worked: Bool?)] = [:]
    var controllingID: InstalledApp.ID?
    /// Per Electron app: the launch option it needs, and whether its running
    /// copy has it, as `playercheck --launch-option` tells it.
    var launchOptions: [InstalledApp.ID: (option: String, running: LaunchOptionAnswer.Running?)] = [:]
    /// A Relaunch running (its app), and how the last one went per app.
    var relaunchingID: InstalledApp.ID?
    var relaunches: [InstalledApp.ID: (text: String, worked: Bool)] = [:]
    /// The check's playercheck, and the Play or Pause's: what Stop ends.
    var process: ToolRun.Running?
    var pressProcess: ToolRun.Running?
    var pressStopped = false
    /// The running check's progress and Stop, on every desktop.
    @ObservationIgnored let panel = CheckPanelController()

    /// A check, a Play/Pause or a Relaunch is running: one at a time.
    var isBusy: Bool { checkingID != nil || controllingID != nil || relaunchingID != nil }

    init() {
        loadReports()
    }

    /// Runs a tool to the end (`ToolRun`, its errors read too): its exit
    /// status and all it printed.
    nonisolated static func runAndWait(_ tool: URL, _ arguments: [String]) async -> (Int32, String) {
        let result = await ToolRun(tool, arguments, readsErrors: true).run()
        return result == .notStarted ? (-1, "couldn't run \(tool.lastPathComponent)") : (result.status, result.text)
    }

    /// playercheck, built into this app's Resources by build.sh.
    let tool = Bundle.main.url(forResource: "playercheck", withExtension: nil)

    func scan() {
        isScanning = true
        Task {
            apps = await InstalledApp.scan(tool: tool)
            isScanning = false
        }
        refreshRunning()
        readClients(full: true)
    }

    func refreshRunning() {
        runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        isTrusted = AXIsProcessTrusted()
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        app.bundleID.map(runningIDs.contains) ?? false
    }
}
