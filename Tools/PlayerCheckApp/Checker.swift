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
    private(set) var finished: [InstalledApp.ID: CheckReport] = [:]
    /// Why the last check of an app didn't finish, while its last finished
    /// check is shown instead.
    var attemptNotes: [InstalledApp.ID: String] = [:]
    /// A check cancelled before it did anything, as a permission it needs
    /// isn't allowed (`CheckExitStatus.permissionMissing`): what it said, and
    /// the first permission missing, for its pane in System Settings.
    var permissionProblems: [InstalledApp.ID: (text: String, missing: CheckReportLine.Permission?)] = [:]
    var checkingID: InstalledApp.ID?
    /// The check running, to tell it from one started after it was stopped.
    private var attempt: UUID?
    var isTrusted = AXIsProcessTrusted()
    /// macOS's own Now Playing list, by bundle ID; why it couldn't be read.
    var clients: [String: NowPlayingListLine] = [:]
    var clientsProblem: String?
    var isReadingClients = false
    /// When the list was last read: the next read asks only for what changed
    /// since (the first reads macOS's log since the Mac started).
    private var clientsReadAt: Date?
    /// A read asked for while another ran (true: a full one), done after it.
    private var readAgain: Bool?
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
    private var process: ToolRun.Running?
    private var pressProcess: ToolRun.Running?
    private var pressStopped = false
    /// The running check's progress and Stop, on every desktop.
    @ObservationIgnored private let panel = CheckPanelController()

    /// A check, a Play/Pause or a Relaunch is running: one at a time.
    var isBusy: Bool { checkingID != nil || controllingID != nil || relaunchingID != nil }

    init() {
        loadReports()
    }

    // MARK: Checks kept between launches

    private struct SavedReport: Codable {
        let lines: [String]
        let date: Date
        /// The checks' kind: 4 from when each way is tested in every window
        /// state (✓ means all of them). Older ones are dropped: their ✓ meant
        /// one state, wherever the window happened to be.
        var version: Int? = SavedReport.currentVersion
        static let currentVersion = 4
    }
    private static let savedReports = URL.applicationSupportDirectory.appending(path: "Player Check/reports.json")

    private func loadReports() {
        guard let data = try? Data(contentsOf: Self.savedReports),
              let saved = try? JSONDecoder().decode([String: SavedReport].self, from: data) else { return }
        finished = saved.filter { $0.value.version == SavedReport.currentVersion }
            .mapValues { CheckReport(state: .finished, lines: $0.lines, date: $0.date) }
        reports = finished
    }

    private func saveReports() {
        let saved = finished.mapValues { SavedReport(lines: $0.lines, date: $0.date) }
        try? FileManager.default.createDirectory(at: Self.savedReports.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: Self.savedReports)
    }

    // MARK: Playing and pausing

    /// Whether its Play and Pause buttons show: some way worked in its last
    /// finished check, in every window state or some. Which one a press uses
    /// depends on the state its window is in then (`controlByState`).
    func hasWorkingWay(_ app: InstalledApp) -> Bool {
        finished[app.id]?.ways.contains { $0.canControl && ($0.mark == .works || $0.mark == .some) } ?? false
    }

    /// Plays or pauses it by the first way that worked in its last check with
    /// its window as it is now: playercheck --window-state tells the state,
    /// then --via that way alone.
    func controlByState(_ app: InstalledApp, _ action: CommandLineOptions.Action) {
        guard !isBusy, let tool, let ways = finished[app.id]?.ways else { return }
        controllingID = app.id
        controls[app.id] = ((action == .play ? "Playing" : "Pausing") + "…", nil)
        Task {
            let (_, output) = await Self.runAndWait(tool, CommandLineOptions.AppQuery.windowState.arguments(app.url.path))
            controllingID = nil
            // Without a window (or not known), only a way that worked in every state.
            let known = WindowStateAnswer(line: output)?.windowState
            guard let way = ways.first(where: { $0.canControl && (known.map($0.passes) ?? ($0.mark == .works)) }), let via = way.via else {
                controls[app.id] = (known.map { "No way worked in its check with its window \($0.title)." }
                                    ?? "No way worked in every window state in its check.", false)
                return
            }
            control(app, action, via: via, note: known.map { "Its window \($0.title): by \(AppDetail.wayName(via))." })
        }
    }

    /// Plays or pauses it by that one way: playercheck --play or --pause
    /// --via `via` tries no other. `stopPress` ends it. `note` goes before
    /// what playercheck says (the window's state and the way chosen).
    func control(_ app: InstalledApp, _ action: CommandLineOptions.Action, via: CheckResult.WayKind, note: String? = nil) {
        guard !isBusy, let tool else { return }
        let run: LineRun
        do {
            run = try LineRun(tool, CommandLineOptions.press(app.url.path, action, via: via))
        } catch {
            controls[app.id] = ("Couldn't run playercheck: \(error.localizedDescription)", false)
            return
        }
        controllingID = app.id
        controls[app.id] = ((action == .play ? "Playing" : "Pausing") + "…", nil)
        pressProcess = run.running
        pressStopped = false
        Task {
            var output: [String] = []
            for await line in run.lines { output.append(line) }
            let status = await run.status()
            let said = output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            controls[app.id] = pressStopped
                ? ("Stopped before it said whether it worked.", false)
                : ((note.map { $0 + " " } ?? "") + said, status == CheckExitStatus.done)
            pressProcess = nil
            controllingID = nil
            readClients()
        }
    }

    /// For an Electron app: the launch option it needs, and whether it runs
    /// with it (`launchOptions`), asked of playercheck.
    func readLaunchOption(_ app: InstalledApp) {
        guard let tool, app.hiddenInterface?.hasPrefix("Electron") == true else { return }
        Task {
            let (status, output) = await Self.runAndWait(tool, CommandLineOptions.AppQuery.launchOption.arguments(app.url.path))
            guard status == CheckExitStatus.done, let answer = LaunchOptionAnswer(line: output), let option = answer.option else {
                launchOptions[app.id] = nil
                return
            }
            launchOptions[app.id] = (option, answer.running)
        }
    }

    /// Quits the app and opens it again with its launch option, in the
    /// background (playercheck --relaunch), then reads the option again.
    func relaunch(_ app: InstalledApp) {
        guard !isBusy, relaunchingID == nil, let tool else { return }
        relaunchingID = app.id
        relaunches[app.id] = nil
        Task {
            let (status, output) = await Self.runAndWait(tool, CommandLineOptions.AppQuery.relaunch.arguments(app.url.path))
            relaunches[app.id] = (output.trimmingCharacters(in: .whitespacesAndNewlines), status == CheckExitStatus.done)
            relaunchingID = nil
            refreshRunning()
            readLaunchOption(app)
        }
    }

    /// Stops a Play or Pause (it may be waiting on an app, or on macOS's
    /// Automation prompt): playercheck turns back off the switches it turned on.
    func stopPress() {
        guard let pressProcess else { return }
        pressStopped = true
        pressProcess.stop()
    }

    /// When the app quits: stops what runs, so no playercheck goes on unwatched.
    func stopAll() {
        stop()
        stopPress()
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

    /// Reads macOS's Now Playing list again: all of it (the log since the
    /// Mac started: seconds on a Mac up for days) at first and when asked,
    /// else only what changed since the last read.
    func readClients(full: Bool = false) {
        guard let tool else {
            clientsProblem = "playercheck is missing from this app: build it with build.sh."
            return
        }
        guard !isReadingClients else {
            readAgain = (readAgain ?? false) || full
            return
        }
        isReadingClients = true
        let since = full ? nil : clientsReadAt
        let started = Date()
        // A little overlap, so nothing written meanwhile is missed.
        let arguments = since.map { CommandLineOptions.nowPlayingList(since: $0.addingTimeInterval(-2)) } ?? CommandLineOptions.nowPlayingList(hours: nil)
        Task {
            let (status, output) = await Checker.runAndWait(tool, arguments)
            if status == CheckExitStatus.done {
                var updated = since == nil ? [:] : clients
                var active: pid_t?
                for line in output.split(separator: "\n") {
                    if let pid = NowPlayingListLine.active(in: line) {
                        active = pid
                    } else if let client = NowPlayingListLine(line: line) {
                        if client.state == NowPlayingListLine.removed {
                            if updated[client.bundleID]?.pid == client.pid { updated[client.bundleID] = nil }
                        } else if client.state == NowPlayingListLine.registered, updated[client.bundleID]?.pid == client.pid {
                            // An update names a client it saw without a state (logged
                            // again, created again): the state known for that process
                            // still holds, as playercheck's own check keeps it.
                        } else {
                            updated[client.bundleID] = client
                        }
                    }
                }
                if let active {
                    updated = updated.mapValues { client in
                        var client = client
                        client.isActive = client.pid == active
                        return client
                    }
                }
                clients = updated
                clientsReadAt = started
                clientsProblem = nil
            } else {
                clients = [:]
                // Nothing kept to update: the next read is a full one.
                clientsReadAt = nil
                clientsProblem = "macOS's own Now Playing list couldn't be read: "
                    + output.trimmingCharacters(in: .whitespacesAndNewlines) + " (it needs an administrator account)."
            }
            isReadingClients = false
            if let again = readAgain {
                readAgain = nil
                readClients(full: again)
            }
        }
    }

    /// Its entry in macOS's Now Playing list, while it runs (a list kept up
    /// to date by changes only may still hold an app that quit).
    func client(of app: InstalledApp) -> NowPlayingListLine? {
        guard isRunning(app) else { return nil }
        return app.bundleID.flatMap { clients[$0] }
    }

    /// The apps that can be in Now Playing: built for it, or listed there now.
    var nowPlayingApps: [InstalledApp] {
        apps.filter { $0.nowPlayingReason != nil || client(of: $0) != nil }
    }

    func refreshRunning() {
        runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        isTrusted = AXIsProcessTrusted()
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        app.bundleID.map(runningIDs.contains) ?? false
    }

    /// Asks macOS for the Accessibility permission: its own request, which
    /// leads to System Settings (the same as AutoHush's).
    nonisolated static func askForAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Opens the app when it isn't running (and gives it time to load its
    /// window and page), then runs playercheck on it. Without the
    /// Accessibility permission, which its menu, page and panel ways need,
    /// macOS is asked for it first, and the check starts once it's allowed
    /// (Stop ends the wait).
    func check(_ app: InstalledApp) {
        guard !isBusy, let tool else { return }
        let token = UUID()
        attempt = token
        checkingID = app.id
        attemptNotes[app.id] = nil
        permissionProblems[app.id] = nil
        refreshRunning()
        let allowing = !isTrusted
        reports[app.id] = CheckReport(state: allowing ? .allowing : isRunning(app) ? .checking : .opening)
        panel.show { resized, dimmed in
            PlayerCheckPanelView(app: app, checker: self, resized: resized, dimmed: dimmed)
        }
        Task {
            if allowing {
                Self.askForAccessibility()
                while !AXIsProcessTrusted() {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard attempt == token else { return } // stopped
                }
                refreshRunning()
            }
            let opening = !isRunning(app)
            reports[app.id]?.state = opening ? .opening : .checking
            if opening {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                // An Electron app opens with the option its page needs to take
                // presses out of view.
                if app.hiddenInterface?.hasPrefix("Electron") == true {
                    let (_, said) = await Self.runAndWait(tool, CommandLineOptions.AppQuery.launchOption.arguments(app.url.path))
                    if let option = LaunchOptionAnswer(line: said)?.option { configuration.arguments = [option] }
                }
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    guard attempt == token else { return }
                    reports[app.id]?.state = .failed("Couldn't open it: \(error.localizedDescription)")
                    endAttempt(app.id)
                    return
                }
                // Stopped meanwhile (and maybe another check started since).
                guard attempt == token else { return }
                reports[app.id]?.state = .checking
                refreshRunning()
                readLaunchOption(app)
            }
            await run(tool, on: app)
        }
    }

    /// The end of a check: a finished one is kept (and saved); one stopped or
    /// failed gives way to the last finished check, if there's one, with a note.
    private func endAttempt(_ id: InstalledApp.ID) {
        if let report = reports[id], report.state == .finished {
            finished[id] = report
            saveReports()
        } else if let report = reports[id], let previous = finished[id] {
            switch report.state {
            case .stopped: attemptNotes[id] = "The check was stopped: the last finished check is shown."
            case .failed where permissionProblems[id] != nil:
                // Its warning says why, above the last finished check.
                break
            case .failed(let reason):
                // macOS's messages end with a full stop already.
                attemptNotes[id] = (reason.hasSuffix(".") ? String(reason.dropLast()) : reason) + ". The last finished check is shown."
            default: break
            }
            reports[id] = previous
        }
        process = nil
        attempt = nil
        checkingID = nil
        panel.hide()
    }

    private func run(_ tool: URL, on app: InstalledApp) async {
        let run: LineRun
        do {
            // --developer: the verdict also says how a built-in player of
            // its kind would be made, as AutoHush's Add an App… doesn't ask.
            run = try LineRun(tool, CommandLineOptions.check(app.url.path, developer: true))
        } catch {
            reports[app.id]?.state = .failed("Couldn't run playercheck: \(error.localizedDescription)")
            endAttempt(app.id)
            return
        }
        self.process = run.running
        let id = app.id
        for await line in run.lines where !line.isEmpty {
            reports[id]?.add(line)
        }
        let status = await run.status()
        if reports[id]?.state == .checking {
            if status == CheckExitStatus.permissionMissing {
                // Cancelled before doing anything: a permission it needs isn't
                // allowed (or not answered), or the app didn't answer whether
                // it is (no permission to show in System Settings).
                let lines = reports[id]?.lines ?? []
                let said = lines.lazy.compactMap { CheckReportLine.notChecked(in: $0) }.last
                    ?? "A permission the check needs isn't allowed."
                permissionProblems[id] = (said, lines.lazy.compactMap { CheckReportLine.missingPermission(in: $0) }.first)
                reports[id]?.state = .failed("The check was cancelled: \(said)")
            } else {
                // Stopped by Escape too, while it blocked the mouse and keyboard.
                reports[id]?.state = status == CheckExitStatus.done ? .finished : CheckExitStatus.isStop(status) ? .stopped
                    : .failed("playercheck ended with status \(status)")
            }
        }
        endAttempt(id)
        refreshRunning()
        readClients()
    }

    /// Stops the check: playercheck plays the app again if a test paused it,
    /// and turns the accessibility switches it turned on back off, first.
    func stop() {
        guard let id = checkingID else { return }
        reports[id]?.state = .stopped
        if let process {
            process.stop()
        } else {
            endAttempt(id) // still opening the app
        }
    }
}

/// What the list says of an app's line in Now Playing.
extension NowPlayingListLine {
    var summary: String { isActive ? "Now Playing (\(state))" : "In Now Playing: \(state)" }
}
