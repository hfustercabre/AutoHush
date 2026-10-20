// Player Check: a window over Sources/PlayerCheck. It lists the apps in the
// Applications folders (/Applications, ~/Applications, /System/Applications,
// with their subfolders: Safari web apps included) that can be in macOS's
// Now Playing list, those macOS lists now first (playercheck's
// --now-playing-list, from macOS's log). Once an app is chosen and the check
// confirmed, it runs playercheck on it (opening it first when needed) and
// shows the ways it could be controlled (each tested with the app's window
// in every state a player's can be in: ✓ all, ⚠ some, ✗ none), the verdict
// (with its developer lines: playercheck --developer) and the full report;
// checks are kept between launches. An app whose check
// found a way that works gets Play and Pause buttons, by the first way that
// worked with its window as it is when pressed (playercheck --window-state),
// and each way found gets its own (playercheck --play/--pause --via …). An
// Electron app running without the launch option its page needs out of view
// gets a Relaunch button (playercheck --launch-option, --relaunch). While a
// check runs, a small panel at the screen's bottom right shows how far it
// has got, with Stop, on every desktop (the check's panel, as AutoHush's Add
// an App… shows it). It runs playercheck as AutoHush does, through the same
// interface (PlayerCheckKit's command line, exit statuses and answers,
// CheckedPlayers' report lines and progress) and AutoHushKit's `ToolRun`.
// Build: sh Tools/PlayerCheckApp/build.sh [folder] (the package's PlayerCheckApp
// product, in an app with playercheck inside it).
import AppKit
import AutoHushKit
import CheckPanel
import CheckedPlayers
import PlayerCheckKit
import SwiftUI

// MARK: - The apps

/// An app found in one of the Applications folders.
struct InstalledApp: Identifiable, Hashable {
    enum Root: CaseIterable {
        case applications, user, system
        var url: URL {
            switch self {
            case .applications: ApplicationFolders.applications
            case .user: ApplicationFolders.user
            case .system: ApplicationFolders.system
            }
        }
        var title: String {
            switch self {
            case .applications: "Applications"
            case .user: "Your Applications (web apps are here)"
            case .system: "System Applications"
            }
        }
    }

    let url: URL
    let name: String
    let bundleID: String?
    let root: Root
    /// The subfolders between its Applications folder and it, e.g. "Utilities".
    let subfolder: String?
    let isSafariWebApp: Bool
    /// What draws its interface, when that keeps it from Accessibility
    /// until a switch is on: "Electron 38.4.0", "Chromium (CEF)", "Flutter"
    /// or a Chromium browser's web app ("Google Chrome web app"), and the
    /// switches a check turns on for it ("Electron's switch, else
    /// VoiceOver's switch"), as playercheck tells them (--now-playing-reasons).
    let hiddenInterface: String?
    let switches: String?
    /// Why it can be in Now Playing, from what it's built with; nil when
    /// nothing shows it can (playercheck --now-playing-reasons).
    let nowPlayingReason: String?
    var id: String { url.path }

    /// For the check's confirmation, as playercheck does it: the switch it
    /// turns on to read the app's interface, which one it leaves on, and
    /// that it may bring the app forward a moment to have its page built.
    /// A Chromium browser's web app's browser ("Google Chrome"), from the
    /// interface playercheck names ("Google Chrome web app"); nil otherwise.
    var webAppBrowser: String? {
        guard let hiddenInterface, hiddenInterface.hasSuffix(" web app") else { return nil }
        return String(hiddenInterface.dropLast(" web app".count))
    }

    var switchNote: String? {
        guard let switches else { return nil }
        if let browser = webAppBrowser {
            return "To read its page, the check turns on \(switches), which reaches all of \(browser)'s windows and tabs, and turns"
                + " it back off after, unless VoiceOver had it on: then it's left on. Each Play or Pause by its page does the same,"
                + " about 2 seconds longer."
        }
        let page = hiddenInterface == "Flutter" ? "interface" : "page"
        return "To read its \(page), the check turns on an accessibility switch (\(switches)) and turns it back off after,"
            + " unless it may have been on already (its \(page) was readable before, or VoiceOver had it on): then it's left on."
            + " If its window is out of sight, \(name) may be brought forward a moment, to its desktop and back, for its \(page) to be built."
    }

    /// Every .app in the Applications folders and their subfolders (not
    /// inside other apps), by name. Why each can be in Now Playing comes from
    /// `tool` (playercheck), asked once for them all.
    static func scan(tool: URL?) async -> [InstalledApp] {
        let found = applications()
        var told: [String: NowPlayingReasonsLine] = [:]
        if let tool, !found.isEmpty {
            let (status, output) = await Checker.runAndWait(tool, CommandLineOptions.nowPlayingReasons(found.map(\.url.path)))
            if status == CheckExitStatus.done {
                for case let line? in output.split(separator: "\n").map({ NowPlayingReasonsLine(line: $0) }) { told[line.path] = line }
            }
        }
        return found.map { app in
            let line = told[app.url.path]
            return InstalledApp(url: app.url, name: app.name, bundleID: app.bundleID, root: app.root, subfolder: app.subfolder,
                                isSafariWebApp: app.bundleID?.hasPrefix("com.apple.Safari.WebApp.") == true,
                                hiddenInterface: line?.interface, switches: line?.switches, nowPlayingReason: line?.reason)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The .app bundles in the Applications folders and their subfolders.
    private static func applications() -> [(url: URL, name: String, bundleID: String?, root: Root, subfolder: String?)] {
        var found: [(url: URL, name: String, bundleID: String?, root: Root, subfolder: String?)] = []
        for root in Root.allCases {
            let base = root.url.standardizedFileURL.path
            guard let items = FileManager.default.enumerator(at: root.url, includingPropertiesForKeys: nil,
                                                             options: [.skipsPackageDescendants, .skipsHiddenFiles])
            else { continue }
            for case let url as URL in items where url.pathExtension == "app" {
                let parent = url.deletingLastPathComponent().standardizedFileURL.path
                var subfolder: String?
                if parent.count > base.count {
                    // Each folder by the name Finder shows ("Chrome Apps", not "Chrome Apps.localized").
                    var path = base
                    subfolder = parent.dropFirst(base.count + 1).split(separator: "/").map { part in
                        path += "/" + part
                        return FileManager.default.displayName(atPath: path)
                    }.joined(separator: " › ")
                }
                let bundleID = Bundle(url: url)?.bundleIdentifier
                found.append((url, AppName.of(appAt: url), bundleID, root, subfolder))
            }
        }
        return found
    }
}

// MARK: - macOS's own Now Playing list

/// An app mediaremoted keeps in Now Playing now, as `playercheck
/// --now-playing-list` reads it from macOS's log (administrators only): its
/// last state (Playing, Paused, Stopped…), or Registered: ready for Now
/// Playing, never said it plays; Removed, gone (`--since` only).
typealias NowPlayingClient = NowPlayingListLine

extension NowPlayingListLine {
    var summary: String { isActive ? "Now Playing (\(state))" : "In Now Playing: \(state)" }
}

// MARK: - A check's report

/// One line of playercheck's "Ways to Control It" (`CheckReportLine.way(in:)`),
/// with the window states under it (those it failed in, or that weren't tested).
struct Way: Identifiable {
    let id: Int
    /// ✓ worked in every window state tested, ⚠ in some, ✗ in none (or not
    /// there), ? found but not tried, – not checked.
    let mark: CheckReportLine.WayMark
    /// The way its title names.
    let kind: CheckResult.WayKind?
    let title: String
    let detail: String
    /// "      ✗ covered: why" → (failed, "covered", "why"); "– …: not tested (…)" → not failed.
    var states: [(failed: Bool, state: String, why: String)] = []

    /// "  ✓ AppleScript: pausing … worked" → works, "AppleScript", "pausing … worked".
    init?(id: Int, line: String) {
        guard let way = CheckReportLine.way(in: line) else { return nil }
        self.id = id
        mark = way.mark
        kind = way.way
        title = way.title
        detail = way.detail
    }

    /// Its playercheck --via, for the ways that can play and pause: AppleScript
    /// once it worked in the check, whatever its kind (`--via script` handles
    /// a play that toggles too), but before that only as the supported
    /// scriptable players have it (commands of their own kind, not tried,
    /// aren't offered); the menu, the page, the Now Playing panel.
    var via: CheckResult.WayKind? {
        kind == .script && detail.contains(CheckReportLine.unlikeScriptablePlayers) ? nil : kind
    }
    /// A way to play and pause with: it worked in the check (in every window
    /// state or some), or was found.
    var canControl: Bool { via != nil && (mark == .works || mark == .some || mark == .notTried) }

    /// Whether it worked in its check with the app's window in `state` (as
    /// `playercheck --window-state` tells it): it worked in every state
    /// tested, or some, and that one isn't listed under it as failed or not
    /// tested. On another desktop, covered there too: the window list can't
    /// tell the two apart.
    func passes(_ state: CheckResult.WindowState) -> Bool {
        guard mark == .works || mark == .some else { return false }
        let wanted = (state == .otherDesktop ? [state, .otherDesktopCovered] : [state]).map(\.title)
        return !states.contains { wanted.contains($0.state) || $0.state == "window states" }
    }
}

/// What playercheck said about one app, as it comes in.
struct Report {
    /// `allowing`: waiting for the Accessibility permission, before anything runs.
    enum State: Equatable { case allowing, opening, checking, finished, stopped, failed(String) }
    var state: State
    var lines: [String] = []
    var date = Date()
    /// How far the check has got, from its lines as they came (`CheckProgress`,
    /// as AutoHush follows it): while it runs.
    var progress = CheckProgress()

    /// Adds a line as it comes.
    mutating func add(_ line: String) {
        lines.append(line)
        progress.add(line)
    }

    /// The lines under a heading (a line that isn't indented), whatever its
    /// case: playercheck's headings are title case, older saved checks' not.
    func section(_ heading: CheckReportLine.Heading) -> [String] {
        guard let start = lines.firstIndex(where: { $0.caseInsensitiveCompare(heading.rawValue) == .orderedSame }) else { return [] }
        return Array(lines[(start + 1)...].prefix { $0.hasPrefix(" ") })
    }
    /// Each way's line, with the more indented lines under it (its window
    /// states) attached to it.
    var ways: [Way] {
        var found: [Way] = []
        for (index, line) in section(.ways).enumerated() {
            if let state = CheckReportLine.wayState(in: line) {
                guard !found.isEmpty else { continue }
                found[found.count - 1].states.append((state.failed, state.state.replacingOccurrences(of: "minimised", with: "minimized"), state.why))
            } else if let way = Way(id: index, line: line) {
                found.append(way)
            }
        }
        return found
    }
    /// The window state the check has the app in now, while it checks.
    var testedState: CheckProgress.WindowStep? { state == .checking ? progress.windowStep : nil }
    /// The same as "covered, 2 of 7".
    var windowState: String? { testedState.map { "\($0.state?.title ?? ""), \($0.index) of \($0.count)" } }
    /// What the check does in that window state: the way it's pressing and
    /// whether it's pausing or playing it again ("By its playback menu:
    /// playing it again"), why the state isn't tested, or the move there.
    var stateActivity: String? {
        guard testedState != nil else { return nil }
        switch progress.activity {
        case .pausing(let way)?: return "By \(AppDetail.wayName(way)): pausing it"
        case .playingAgain(let way)?: return "By \(AppDetail.wayName(way)): playing it again"
        case .untested?:
            let text = lines.last { $0.hasPrefix(CheckReportLine.notTested) }?.trimmingCharacters(in: .whitespaces) ?? ""
            return text.prefix(1).uppercased() + text.dropFirst()
        case .moving?, nil: return "Moving its window there"
        }
    }
    var verdict: String {
        section(.verdict).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }
    /// What playercheck asks of whoever runs it while it waits ("start
    /// playing something in <app>; …"), in its own words: the app must play
    /// for the test. Asked until it's answered (it plays, it paused,
    /// Accessibility is decided), the wait ends ("stopped…", "it didn't…")
    /// or its section does (`CheckProgress.request`).
    var request: String? {
        guard state == .checking, progress.request != nil,
              let text = lines.lazy.reversed().compactMap({ CheckReportLine.requestText(in: $0) }).first else { return nil }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
    /// The whole report, with a blank line before each heading.
    var text: String {
        lines.enumerated().map { index, line in
            index > 0 && !line.hasPrefix(" ") ? "\n" + line : line
        }.joined(separator: "\n")
    }
}

// MARK: - Running playercheck

/// playercheck started, as AutoHush starts it (`ToolRun.start`): its lines
/// as it prints them (its errors too), and its exit status, both awaited
/// without blocking the main thread.
struct LineRun {
    /// What Stop ends.
    let running: ToolRun.Running
    let lines: AsyncStream<String>
    private let ended: AsyncStream<Int32>

    init(_ tool: URL, _ arguments: [String]) throws {
        let (lines, line) = AsyncStream.makeStream(of: String.self)
        let (ended, end) = AsyncStream.makeStream(of: Int32.self)
        // Its end comes after its last line.
        running = try ToolRun(tool, arguments, readsErrors: true).start(onLine: { line.yield($0) }, onEnd: { result in
            line.finish()
            end.yield(result.status)
            end.finish()
        })
        self.lines = lines
        self.ended = ended
    }

    /// Its exit status, once it has ended.
    func status() async -> Int32 {
        var status: Int32 = -1
        for await code in ended { status = code }
        return status
    }
}

// MARK: - The model

@MainActor @Observable
final class Checker {
    var apps: [InstalledApp] = []
    var isScanning = false
    var runningIDs: Set<String> = []
    /// What's shown per app: its check running, else its last finished one
    /// (else a check that stopped or failed).
    var reports: [InstalledApp.ID: Report] = [:]
    /// The last finished check per app, kept between launches: a check
    /// stopped or failed leaves it in place.
    private(set) var finished: [InstalledApp.ID: Report] = [:]
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
    var clients: [String: NowPlayingClient] = [:]
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
            .mapValues { Report(state: .finished, lines: $0.lines, date: $0.date) }
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
        let tool = self.tool
        Task {
            let found = await Task.detached { await InstalledApp.scan(tool: tool) }.value
            apps = found
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
                    } else if let client = NowPlayingClient(line: line) {
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
    func client(of app: InstalledApp) -> NowPlayingClient? {
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
        reports[app.id] = Report(state: allowing ? .allowing : isRunning(app) ? .checking : .opening)
        panel.show { resized, dimmed in
            CheckPanelView(app: app, checker: self, resized: resized, dimmed: dimmed)
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

// MARK: - Views

struct ContentView: View {
    let checker: Checker
    @State private var selection: InstalledApp.ID?
    @State private var search = ""

    private var shown: [InstalledApp] {
        let apps = checker.nowPlayingApps
        return search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                let listed = shown.filter { checker.client(of: $0) != nil }
                if !listed.isEmpty {
                    Section("In Now Playing Now") {
                        ForEach(listed) { app in
                            AppRow(app: app, isRunning: checker.isRunning(app), client: checker.client(of: app),
                                   isChecked: checker.finished[app.id] != nil).tag(app.id)
                        }
                    }
                }
                ForEach(InstalledApp.Root.allCases, id: \.self) { root in
                    let apps = shown.filter { $0.root == root && checker.client(of: $0) == nil }
                    if !apps.isEmpty {
                        Section(root.title) {
                            ForEach(apps) { app in
                                AppRow(app: app, isRunning: checker.isRunning(app), client: nil,
                                       isChecked: checker.finished[app.id] != nil).tag(app.id)
                            }
                        }
                    }
                }
            }
            .overlay {
                if checker.isScanning && checker.apps.isEmpty {
                    ProgressView("Looking in the Applications folders…")
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search apps")
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    Text("\(checker.nowPlayingApps.count) of \(checker.apps.count) apps can be in Now Playing")
                    if checker.isReadingClients {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Reading macOS's Now Playing list…")
                        }
                    } else if let problem = checker.clientsProblem {
                        Text(problem).multilineTextAlignment(.center)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(8)
                .background(.bar)
            }
        } detail: {
            if let app = checker.apps.first(where: { $0.id == selection }) {
                AppDetail(app: app, checker: checker)
                    .id(app.id)
            } else {
                ContentUnavailableView("Choose an App", systemImage: "music.note.list",
                                       description: Text("Player Check finds out whether AutoHush could pause and play it, and how."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button { checker.scan() } label: { Label("Look Again", systemImage: "arrow.clockwise") }
                    .disabled(checker.isScanning)
                    .help("Look in the Applications folders and macOS's Now Playing list again")
            }
        }
        .onAppear { checker.scan() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            checker.refreshRunning()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            checker.refreshRunning()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checker.refreshRunning()
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}

struct AppRow: View {
    let app: InstalledApp
    let isRunning: Bool
    let client: NowPlayingClient?
    let isChecked: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                let notes = [client?.summary, isChecked ? "checked" : nil, app.subfolder, app.nowPlayingReason]
                    .compactMap { $0 }
                if !notes.isEmpty {
                    Text(notes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isRunning {
                Circle().fill(.green).frame(width: 7, height: 7).help("Running")
            }
        }
    }
}

struct AppDetail: View {
    let app: InstalledApp
    let checker: Checker
    @State private var confirming = false
    @State private var confirmingRelaunch = false
    @State private var showsReport = false

    private var report: Report? { checker.reports[app.id] }
    private var isChecking: Bool { checker.checkingID == app.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                // While a check waits for it, its own request says it instead.
                if !checker.isTrusted, !(isChecking && report?.state == .allowing) { permissionNote }
                launchOptionNote
                controls
                if checker.hasWorkingWay(app) {
                    playAndPause
                } else if checker.controllingID == app.id || checker.controls[app.id] != nil {
                    // A way's own buttons, with no way that worked to head the section.
                    pressStatus
                }
                if let report { results(report) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Check “\(app.name)”?", isPresented: $confirming) {
            Button(checker.isRunning(app) ? "Check" : "Open and Check") { checker.check(app) }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmation)
        }
        .alert("Relaunch “\(app.name)”?", isPresented: $confirmingRelaunch) {
            Button("Relaunch") { checker.relaunch(app) }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(app.name) quits and opens again with \(checker.launchOptions[app.id]?.option ?? "its launch option"), in the background."
                 + " Whatever it's playing stops.")
        }
        .task(id: checker.isRunning(app)) { checker.readLaunchOption(app) }
    }

    /// For an Electron app running without the option its page needs to take
    /// presses out of view: a warning (a check now would show those window
    /// states failing) and a button to relaunch it with it.
    @ViewBuilder private var launchOptionNote: some View {
        if let launch = checker.launchOptions[app.id], launch.running == .no || checker.relaunchingID == app.id {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(app.name) is running without Chromium's \(launch.option): its page can't be pressed while its window is covered"
                      + " or on another desktop, so a check now would show those states failing.",
                      systemImage: "exclamationmark.triangle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Relaunch \(app.name) With It") { confirmingRelaunch = true }
                        .disabled(checker.isBusy || checker.tool == nil)
                    if checker.relaunchingID == app.id {
                        ProgressView().controlSize(.small)
                        Text("Relaunching…").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        if let result = checker.relaunches[app.id], checker.relaunchingID != app.id {
            Label(result.text, systemImage: result.worked ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.worked ? .green : .red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.title2.weight(.semibold))
                Text(app.bundleID ?? "no bundle ID").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text(app.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let reason = app.nowPlayingReason {
                    Text("Can be in Now Playing: \(reason)").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Tag(text: checker.isRunning(app) ? "Running" : "Not running", tint: checker.isRunning(app) ? .green : .secondary)
                    if let client = checker.client(of: app) { Tag(text: client.summary, tint: .pink) }
                    if app.isSafariWebApp { Tag(text: "Safari web app", tint: .blue) }
                    if let interface = app.hiddenInterface { Tag(text: interface, tint: .purple) }
                }
                .padding(.top, 2)
            }
        }
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Privacy & Security at a permission's list (Audio Recording is under
    /// Screen & System Audio Recording).
    static func openPrivacySettings(for permission: CheckReportLine.Permission) {
        let pane = switch permission {
        case .accessibility: "Privacy_Accessibility"
        case .audioRecording: "Privacy_ScreenCapture"
        case .automation: "Privacy_Automation"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    private var permissionNote: some View {
        GroupBox {
            HStack {
                Label("Player Check needs the Accessibility permission to read menus and pages.", systemImage: "exclamationmark.triangle")
                Spacer()
                Button("Open Settings") { Self.openAccessibilitySettings() }
            }
            .padding(4)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(report == nil ? "Check…" : "Check Again…") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(checker.isBusy || checker.tool == nil)
                if isChecking {
                    Button("Stop") { checker.stop() }
                    ProgressView().controlSize(.small)
                    Text(report?.state == .allowing ? "Waiting for the Accessibility permission…"
                         : report?.state == .opening ? "Opening \(app.name)…" : report?.request != nil ? "Waiting for you…"
                         : report?.windowState.map { "Checking: its window \($0)…" } ?? "Checking…")
                        .foregroundStyle(.secondary)
                }
            }
            if isChecking, report?.state == .allowing {
                // Asked of macOS: the check starts by itself once it's allowed.
                VStack(alignment: .leading, spacing: 8) {
                    // Not named by its pane: macOS 27 calls it Device Control and Data Access.
                    Label("Turn on Player Check in the list System Settings opens (macOS's request leads there, or the button below). The check starts as soon as it's allowed.",
                          systemImage: "hand.raised")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings") { Self.openAccessibilitySettings() }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            if isChecking, let request = report?.request {
                // The test needs the app playing: the check asks, then goes on by itself.
                Label(request, systemImage: "play.circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isChecking, let problem = checker.permissionProblems[app.id] {
                // Cancelled before it did anything (no window moved, nothing pressed).
                VStack(alignment: .leading, spacing: 8) {
                    Label("The check was cancelled before it did anything: \(problem.text)", systemImage: "exclamationmark.triangle")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if let missing = problem.missing {
                        Button("Open System Settings") { Self.openPrivacySettings(for: missing) }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            if checker.tool == nil {
                Text("playercheck is missing from this app: build it with build.sh.").foregroundStyle(.red)
            }
        }
    }

    /// Play and Pause, by the first way that worked in its check with the
    /// app's window in the state it's in when pressed, alone.
    private var playAndPause: some View {
        let running = checker.isRunning(app)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Play and Pause").font(.headline)
            HStack {
                Button { checker.controlByState(app, .play) } label: { Label("Play", systemImage: "play.fill") }
                Button { checker.controlByState(app, .pause) } label: { Label("Pause", systemImage: "pause.fill") }
            }
            .disabled(checker.isBusy || !running || checker.tool == nil)
            Text(!running ? "Open it first: it isn't running."
                 : "By the first way that worked in its check with its window as it is when pressed (covered, minimized, …).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            pressStatus
        }
    }

    /// A Play or Pause of this app: running (with Stop), else its result.
    @ViewBuilder private var pressStatus: some View {
        if checker.controllingID == app.id {
            HStack {
                ProgressView().controlSize(.small)
                Text(checker.controls[app.id]?.text ?? "…").foregroundStyle(.secondary)
                Button("Stop") { checker.stopPress() }
            }
        } else if let result = checker.controls[app.id], let worked = result.worked {
            Label(result.text, systemImage: worked ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(worked ? .green : .red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    nonisolated static func wayName(_ way: CheckResult.WayKind) -> String {
        switch way {
        case .script: "AppleScript"
        case .menu: "its playback menu"
        case .page: "its page's button"
        case .panel: "its row in the Now Playing panel"
        }
    }

    private var confirmation: String {
        var parts: [String] = []
        if !checker.isTrusted {
            parts.append("It needs the Accessibility permission first: macOS asks for it, and the check starts once it's allowed.")
        }
        if !checker.isRunning(app) { parts.append("It isn't running: Player Check opens it first, in the background.") }
        parts.append("Before anything else, it makes sure Player Check has every permission a check needs: Accessibility, Audio Recording, and Automation for \(app.name) if it can be scripted; macOS asks for any not decided yet, and without all of them the check is cancelled before it does anything.")
        if let browser = app.webAppBrowser {
            parts.append("\(browser) is muted all through the check, its other tabs and web apps too (a call in it as well), and heard again at the end.")
        } else {
            parts.append("\(app.name) is muted all through the check (you won't hear it; Player Check still hears whether it plays) and heard again at the end.")
        }
        parts.append("It reads its scripting dictionary, its menus, its sound and Now Playing, and its page's buttons if it shows a page.")
        parts.append("Before it moves anything, \(app.name) must be playing: if it isn't, you're asked to start it, and the check waits up to 2 minutes.")
        parts.append("Then it tests each way to control it: it pauses \(app.name) and plays it again by each, the menu bar's Now Playing panel included (it shows for a moment).")
        parts.append("It does so with \(app.name)'s window in each state: visible, covered (Player Check puts a window over it), on another desktop, covered there, full screen, minimized and hidden. Player Check moves the window there itself and comes back to the front each time; for the desktops it drags the window with the pointer and Control-arrow, so from the first move until the window is put back your clicks, scrolling and keys are blocked (the pointer still moves, except during a drag) and the screen dims, apart from the panel. The panel's Stop and Escape still work, and stop the check; whenever the check asks you something, they're all yours again. Player Check's own window may move aside. Everything is put back as it was at the end. It takes about 3 minutes.")
        parts.append("A small panel at the bottom right of the screen shows how far it has got, with Stop, on every desktop.")
        if let launch = checker.launchOptions[app.id], launch.running == .no {
            parts.append("\(app.name) is running without \(launch.option): its page's presses may fail while its window is covered or on another desktop.")
        }
        if let note = app.switchNote { parts.append(note) }
        return parts.joined(separator: " ")
    }

    @ViewBuilder private func results(_ report: Report) -> some View {
        if let note = checker.attemptNotes[app.id] {
            Label(note, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
        }
        if case .failed(let reason) = report.state, checker.permissionProblems[app.id] == nil {
            Label(reason, systemImage: "xmark.octagon").foregroundStyle(.red)
        } else if report.state == .stopped {
            Label("Stopped: the report is incomplete.", systemImage: "stop.circle").foregroundStyle(.secondary)
        }
        let ways = report.ways
        if !ways.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ways to Control It").font(.headline)
                ForEach(ways) { way in
                    // Each way's own buttons use that way alone.
                    let usable = way.canControl && checker.isRunning(app) && report.state == .finished
                    WayRow(way: way, control: usable ? way.via.map { via in { checker.control(app, $0, via: via) } } : nil,
                           isBusy: checker.isBusy)
                }
                Text("✓ worked in every window state  ·  ⚠ in some  ·  ✗ in none, or not there  ·  ? not tried  ·  – not checked")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if !report.verdict.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("For AutoHush").font(.headline)
                Text(report.verdict).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
        if report.state == .finished {
            Text("Checked \(report.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
        }
        DisclosureGroup(isExpanded: Binding(get: { showsReport || (isChecking && ways.isEmpty) }, set: { showsReport = $0 })) {
            VStack(alignment: .trailing, spacing: 6) {
                Text(report.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Button("Copy Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.text, forType: .string)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Full report").font(.headline)
        }
    }
}

struct WayRow: View {
    let way: Way
    /// Plays or pauses it this way; nil: no buttons.
    var control: ((CommandLineOptions.Action) -> Void)?
    var isBusy = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(way.title).fontWeight(.medium)
                    if !way.detail.isEmpty {
                        Text(way.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    // The window states it failed in, and those not tested.
                    ForEach(way.states.indices, id: \.self) { index in
                        let state = way.states[index]
                        Label {
                            Text("\(Text(state.state).fontWeight(.medium)): \(state.why)")
                        } icon: {
                            Image(systemName: state.failed ? "xmark" : "minus")
                        }
                        .font(.caption)
                        .foregroundStyle(state.failed ? Color.orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(way.title). \(way.detail)"
                                + way.states.map { ". \($0.failed ? "Failed" : "Not tested") \($0.state): \($0.why)" }.joined())
            Spacer(minLength: 8)
            if let control, let via = way.via {
                let name = AppDetail.wayName(via)
                Button { control(.play) } label: { Image(systemName: "play.fill") }
                    .help("Play by \(name)").accessibilityLabel("Play by \(name)")
                Button { control(.pause) } label: { Image(systemName: "pause.fill") }
                    .help("Pause by \(name)").accessibilityLabel("Pause by \(name)")
            }
        }
        .buttonStyle(.bordered)
        .disabled(isBusy)
    }

    private var symbol: String {
        switch way.mark {
        case .works: "checkmark.circle.fill"
        case .some: "exclamationmark.triangle.fill"
        case .notTried: "questionmark.circle.fill"
        case .none: "xmark.circle.fill"
        case .notChecked: "minus.circle"
        }
    }
    private var tint: Color {
        switch way.mark {
        case .works: .green
        case .some: .orange
        case .notTried: .orange
        case .none: .red
        case .notChecked: .secondary
        }
    }
    private var label: String {
        switch way.mark {
        case .works: "Works"
        case .some: "Works in some states"
        case .notTried: "Found, not tried"
        case .none: "No"
        case .notChecked: "Not checked"
        }
    }
}

struct Tag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text).font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - The check's panel

/// What the check's panel shows (`CheckPanelController`, as AutoHush's: a
/// small panel at the bottom right of the screen while the check runs, on
/// every desktop, full screen apps' too, and a shade dimming every screen
/// but it while playercheck blocks the mouse and keyboard): the app, what
/// the check is doing, Stop; what it asks of you (with the time left), or
/// the window states as segments (each one filled once tested), the one
/// it's in and the way it's pressing; and, while the mouse and keyboard are
/// blocked, that they are.
struct CheckPanelView: View {
    let app: InstalledApp
    let checker: Checker
    /// Its size, for the panel to fit it.
    let resized: (CGSize) -> Void
    /// Whether the screen is dimmed: while input is blocked.
    let dimmed: (Bool) -> Void

    private var report: Report? { checker.reports[app.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable().frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Checking \(app.name)").font(.headline).lineLimit(1)
                    Text(stage).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Stop") { checker.stop() }
                    .disabled(report?.state == .stopped)
            }
            if let request = report?.request {
                requestNote(request)
            } else if report?.state == .allowing {
                note("Turn on Player Check in the list System Settings opens", detail: "The check starts as soon as it's allowed.",
                     systemImage: "checkmark.shield")
            } else if let step = report?.testedState {
                progress(step)
            }
            if inputBlocked {
                // As the window's warnings: the check drags windows with the pointer.
                Label("Clicks, scrolling and keys are blocked until it ends. Stop or Escape ends the check.", systemImage: "hand.raised")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .frame(width: 310)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { resized($0) }
        .onChange(of: inputBlocked, initial: true) { _, blocked in dimmed(blocked) }
    }

    /// What the check is doing, by the report's section.
    private var stage: String {
        guard let report else { return "" }
        switch report.state {
        case .allowing: return "Waiting for the Accessibility permission"
        case .opening: return "Opening \(app.name)…"
        case .stopped: return "Stopping: putting everything back as it was…"
        case .finished, .failed: return ""
        case .checking: break
        }
        if report.request != nil { return "Waiting for you" }
        switch report.progress.stage {
        case .permissions: return "Checking permissions"
        case .playing: return "Checking that it plays"
        case .movingWindow: return "Moving its window to where the test starts"
        case .readingPage: return "Reading its page"
        case .testing: return "Testing its window states"
        case .finishing: return "Writing the report"
        case .reading: return "Reading its dictionary, menus and sound"
        }
    }

    /// From playercheck's "blocked" line until it says they're free again,
    /// a stop's put-back included; not while it asks something of you,
    /// when it lifts the block.
    private var inputBlocked: Bool {
        guard let report, report.state == .checking || report.state == .stopped else { return false }
        return report.progress.blocksInput
    }

    /// The request ("start playing something in <app>; the test goes on …
    /// (up to 2 minutes). …"): what's asked, then the rest with the time left.
    private func requestNote(_ request: String) -> some View {
        let cut = [request.range(of: "; "), request.range(of: ": ")].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound }
        let asked = cut.map { String(request[..<$0.lowerBound]) } ?? request
        var rest = cut.map { String(request[$0.upperBound...]) } ?? ""
        if !rest.isEmpty { rest = rest.prefix(1).uppercased() + rest.dropFirst() + (rest.hasSuffix(".") ? "" : ".") }
        let symbol = asked.hasPrefix("Pause") ? "pause.circle" : asked.hasPrefix("Allow") ? "checkmark.shield" : "play.circle"
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            note(asked, detail: Self.withTimeLeft(rest, since: report?.progress.requestSince, now: context.date), systemImage: symbol)
        }
    }

    /// "(up to 2 minutes)" as the time left since the request came ("(1:48 left)").
    static func withTimeLeft(_ text: String, since: Date?, now: Date) -> String {
        guard let since, let start = text.range(of: "up to "),
              let unit = text.range(of: " minute", range: start.upperBound..<text.endIndex),
              let minutes = Int(text[start.upperBound..<unit.lowerBound]) else { return text }
        let end = text[unit.upperBound...].hasPrefix("s") ? text.index(after: unit.upperBound) : unit.upperBound
        let left = max(0, Int(since.addingTimeInterval(Double(minutes * 60)).timeIntervalSince(now).rounded()))
        return text.replacingCharacters(in: start.lowerBound..<end, with: String(format: "%d:%02d left", left / 60, left % 60))
    }

    /// Player Check's look for the parts both apps' panels draw.
    private static let look = CheckPanelLook(caption: .caption, warningFill: .orange.opacity(0.12), track: .secondary.opacity(0.22))

    /// The main window's orange note: what's asked of you, and more under it.
    private func note(_ text: String, detail: String, systemImage: String) -> some View {
        CheckRequestNote(text, detail: detail, symbol: systemImage, look: Self.look)
    }

    /// The window states as segments, the one it's in, and what it does there.
    private func progress(_ step: CheckProgress.WindowStep) -> some View {
        let title = step.state?.title ?? ""
        let activity = report?.stateActivity ?? ""
        return CheckWindowStepView(index: step.index, count: step.count, name: title.prefix(1).uppercased() + title.dropFirst(),
                                   stepText: "\(step.index) of \(step.count)", activity: activity,
                                   accessibilityText: "Window state \(step.index) of \(step.count): \(title). \(activity)", look: Self.look)
    }
}

// MARK: - The app

/// Holds the checker for the app's whole life, not the window's: closing
/// the window quits the app, and its view may be gone by then, so the check
/// or Play/Pause still running is stopped here.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let checker = Checker()
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { checker.stopAll() }
}

@main
struct PlayerCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Player Check", id: "main") {
            ContentView(checker: delegate.checker)
                .neverFullScreen()
        }
        .defaultSize(width: 980, height: 680)
    }
}

private extension View {
    /// Never full screen, from macOS 15; an AppKit collection behavior set
    /// on the window didn't hold, so before it the green button still can.
    @ViewBuilder func neverFullScreen() -> some View {
        if #available(macOS 15, *) { windowFullScreenBehavior(.disabled) } else { self }
    }
}
