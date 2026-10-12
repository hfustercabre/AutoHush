// Player Check: a window over Tools/PlayerCheck. It lists the apps in the
// Applications folders (/Applications, ~/Applications, /System/Applications,
// with their subfolders: Safari web apps included) that can be in macOS's
// Now Playing list, those macOS lists now first (playercheck's
// --now-playing-list, from macOS's log). Once an app is chosen and the check
// confirmed, it runs playercheck on it (opening it first when needed) and
// shows the ways it could be controlled (each tested with the app's window
// in every state a player's can be in: ✓ all, ⚠ some, ✗ none), the verdict
// and the full report; checks are kept between launches. An app whose check
// found a way that works gets Play and Pause buttons, by the first way that
// worked with its window as it is when pressed (playercheck --window-state),
// and each way found gets its own (playercheck --play/--pause --via …). An
// Electron app running without the launch option its page needs out of view
// gets a Relaunch button (playercheck --launch-option, --relaunch).
// Build: sh Tools/PlayerCheckApp/build.sh [folder]
import AppKit
import SwiftUI

// MARK: - The apps

/// An app found in one of the Applications folders.
struct InstalledApp: Identifiable, Hashable {
    enum Root: CaseIterable {
        case applications, user, system
        var url: URL {
            switch self {
            case .applications: URL(fileURLWithPath: "/Applications")
            case .user: URL(fileURLWithPath: NSHomeDirectory() + "/Applications")
            case .system: URL(fileURLWithPath: "/System/Applications")
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
    let isChromeWebApp: Bool
    /// What draws its interface, when that keeps it from Accessibility
    /// until a switch is on: "Electron 38.4.0", "Chromium (CEF)" or
    /// "Flutter", and the switches a check turns on for it ("Electron's
    /// switch, else VoiceOver's switch"), as playercheck tells them
    /// (--now-playing-reasons).
    let hiddenInterface: String?
    let switches: String?
    /// Why it can be in Now Playing, from what it's built with; nil when
    /// nothing shows it can (playercheck --now-playing-reasons).
    let nowPlayingReason: String?
    var id: String { url.path }

    /// For the check's confirmation, as playercheck does it: the switch it
    /// turns on to read the app's interface, which one it leaves on, and
    /// that it may bring the app forward a moment to have its page built.
    var switchNote: String? {
        guard let switches else { return nil }
        let page = hiddenInterface == "Flutter" ? "interface" : "page"
        return "To read its \(page), the check turns on an accessibility switch (\(switches)) and turns it back off after,"
            + " unless it may have been on already (its \(page) was readable before, or VoiceOver had it on): then it's left on."
            + " If its window is out of sight, \(name) may be brought forward a moment, to its desktop and back, for its \(page) to be built."
    }

    /// Every .app in the Applications folders and their subfolders (not
    /// inside other apps), by name. Why each can be in Now Playing comes from
    /// `tool` (playercheck), asked once for them all.
    static func scan(tool: URL?) -> [InstalledApp] {
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
                var name = FileManager.default.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                found.append((url, name, bundleID, root, subfolder))
            }
        }
        // "<path>\t<reason>\t<framework>\t<switches>", each empty when none.
        var told: [String: [String]] = [:]
        if let tool, !found.isEmpty {
            let (status, output) = Checker.runAndWait(tool, ["--now-playing-reasons"] + found.map(\.url.path))
            if status == 0 {
                for line in output.split(separator: "\n") {
                    let parts = line.components(separatedBy: "\t")
                    if parts.count == 4 { told[parts[0]] = parts[1...].map { $0 } }
                }
            }
        }
        return found.map { app in
            let columns = told[app.url.path]?.map { $0.isEmpty ? nil : $0 } ?? [nil, nil, nil]
            return InstalledApp(url: app.url, name: app.name, bundleID: app.bundleID, root: app.root, subfolder: app.subfolder,
                                isSafariWebApp: app.bundleID?.hasPrefix("com.apple.Safari.WebApp.") == true,
                                isChromeWebApp: app.bundleID?.hasPrefix("com.google.Chrome.app.") == true,
                                hiddenInterface: columns[1], switches: columns[2], nowPlayingReason: columns[0])
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - macOS's own Now Playing list

/// An app mediaremoted keeps in Now Playing now, as `playercheck
/// --now-playing-list` reads it from macOS's log (administrators only).
struct NowPlayingClient {
    let bundleID: String
    let pid: String
    /// Its last state (Playing, Paused, Stopped…), or Registered: ready for
    /// Now Playing, never said it plays; Removed, gone (`--since` only).
    let state: String
    /// The active one: the Now Playing app.
    var isActive: Bool

    /// "<bundle ID>\t<pid>\t<state>\t<1 if active>\t<name>"
    init?(line: String) {
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 4 else { return nil }
        bundleID = parts[0]
        pid = parts[1]
        state = parts[2]
        isActive = parts[3] == "1"
    }

    var summary: String { isActive ? "Now Playing (\(state))" : "In Now Playing: \(state)" }
}

// MARK: - A check's report

/// One line of playercheck's "Ways to control it", with the window states
/// under it (those it failed in, or that weren't tested).
struct Way: Identifiable {
    /// ✓ worked in every window state tested, ⚠ in some, ✗ in none (or not
    /// there), ? found but not tried, – not checked.
    enum Mark { case works, some, found, no, notChecked }
    let id: Int
    let mark: Mark
    let title: String
    let detail: String
    /// "      ✗ covered: why" → (failed, "covered", "why"); "– …: not tested (…)" → not failed.
    var states: [(failed: Bool, state: String, why: String)] = []

    /// "  ✓ AppleScript: pausing … worked" → works, "AppleScript", "pausing … worked".
    init?(id: Int, line: String) {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return nil }
        switch first {
        case "✓": mark = .works
        case "⚠": mark = .some
        case "?": mark = .found
        case "✗": mark = .no
        case "–": mark = .notChecked
        default: return nil
        }
        let rest = text.dropFirst().trimmingCharacters(in: .whitespaces)
        if let colon = rest.range(of: ": ") {
            title = String(rest[..<colon.lowerBound])
            detail = String(rest[colon.upperBound...])
        } else {
            title = rest
            detail = ""
        }
        self.id = id
    }

    /// Its playercheck --via, for the ways that can play and pause: AppleScript
    /// once it worked in the check, whatever its kind (`--via script` handles
    /// VLC's toggling play too), but before that only as Spotify's (commands
    /// of their own kind, not tried, aren't offered); the menu, the page, the
    /// Now Playing panel.
    var via: String? {
        if title == "AppleScript", !detail.contains("not as Spotify") { return "script" }
        if title.hasPrefix("Playback menu") { return "menu" }
        if title.hasPrefix("Page button") { return "page" }
        if title == "Now Playing panel" { return "panel" }
        return nil
    }
    /// A way to play and pause with: it worked in the check (in every window
    /// state or some), or was found.
    var canControl: Bool { via != nil && (mark == .works || mark == .some || mark == .found) }

    /// Whether it worked in its check with the app's window in `state` (as
    /// `playercheck --window-state` names it): it worked in every state
    /// tested, or some, and that one isn't listed under it as failed or not
    /// tested. On another desktop, covered there too: the window list can't
    /// tell the two apart.
    func passes(_ state: String) -> Bool {
        guard mark == .works || mark == .some else { return false }
        let wanted = state == "on another desktop" ? [state, "covered on another desktop"] : [state]
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

    /// The lines under a heading (a line that isn't indented).
    func section(_ title: String) -> [String] {
        guard let start = lines.firstIndex(of: title) else { return [] }
        return Array(lines[(start + 1)...].prefix { $0.hasPrefix(" ") })
    }
    /// Each way's line, with the more indented lines under it (its window
    /// states) attached to it.
    var ways: [Way] {
        var found: [Way] = []
        for (index, line) in section("Ways to control it").enumerated() {
            if line.hasPrefix("      ") {
                let text = line.trimmingCharacters(in: .whitespaces)
                guard let mark = text.first, !found.isEmpty, let colon = text.range(of: ": ") else { continue }
                let state = String(text[text.index(after: text.startIndex)..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
                found[found.count - 1].states.append((mark == "✗", state, String(text[colon.upperBound...])))
            } else if let way = Way(id: index, line: line) {
                found.append(way)
            }
        }
        return found
    }
    /// The window state the check has the app in now ("covered, 2 of 7"),
    /// from its last "State N of M: <state>" line.
    var windowState: String? {
        guard state == .checking, let line = lines.last(where: { $0.hasPrefix("  State ") }),
              let colon = line.range(of: ": ") else { return nil }
        let count = line.dropFirst("  State ".count)[..<colon.lowerBound]
        return "\(line[colon.upperBound...]), \(count)"
    }
    var verdict: String {
        section("Verdict").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }
    /// What playercheck asks of whoever runs it while it waits ("start
    /// playing something in Deezer; …"): the app must play for the test.
    var request: String? {
        guard state == .checking, let last = lines.last, last.hasPrefix("  waiting: ") else { return nil }
        let text = last.dropFirst("  waiting: ".count)
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

/// playercheck started: its lines as it prints them (its errors too), and
/// its exit status, awaited without blocking the main thread (waitUntilExit
/// would spin its run loop).
struct ToolRun {
    let process: Process
    let lines: AsyncStream<String>
    private let ended: AsyncStream<Int32>

    init(_ tool: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        // Set before it starts, so its end can't come first.
        ended = AsyncStream { continuation in
            process.terminationHandler = { continuation.yield($0.terminationStatus); continuation.finish() }
        }
        try process.run()
        self.process = process
        let handle = pipe.fileHandleForReading
        lines = AsyncStream { continuation in
            Thread.detachNewThread {
                var pending = Data()
                while case let data = handle.availableData, !data.isEmpty {
                    pending.append(data)
                    while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                        continuation.yield(String(decoding: pending[..<newline], as: UTF8.self))
                        pending.removeSubrange(...newline)
                    }
                }
                if !pending.isEmpty { continuation.yield(String(decoding: pending, as: UTF8.self)) }
                continuation.finish()
            }
        }
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
    /// isn't allowed (playercheck's exit status 3): what it said, and the
    /// first permission missing, for its pane in System Settings.
    var permissionProblems: [InstalledApp.ID: (text: String, missing: String)] = [:]
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
    /// copy has it ("yes", "no", "not running"), as `playercheck
    /// --launch-option` tells it.
    var launchOptions: [InstalledApp.ID: (option: String, running: String)] = [:]
    /// A Relaunch running (its app), and how the last one went per app.
    var relaunchingID: InstalledApp.ID?
    var relaunches: [InstalledApp.ID: (text: String, worked: Bool)] = [:]
    /// The check's playercheck, and the Play or Pause's: what Stop ends.
    private var process: Process?
    private var pressProcess: Process?
    private var pressStopped = false

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
    /// its window as it is now (the user, 2026-10-12): playercheck
    /// --window-state tells the state, then --via that way alone.
    func controlByState(_ app: InstalledApp, _ action: String) {
        guard !isBusy, let tool, let ways = finished[app.id]?.ways else { return }
        controllingID = app.id
        controls[app.id] = ((action == "play" ? "Playing" : "Pausing") + "…", nil)
        Task {
            let (_, output) = await Task.detached { Self.runAndWait(tool, ["--window-state", app.url.path]) }.value
            let state = output.trimmingCharacters(in: .whitespacesAndNewlines)
            controllingID = nil
            // Without a window (or not known), only a way that worked in every state.
            let known = !state.isEmpty && state != "no window" && state != "not running" && !state.contains(" found")
            guard let way = ways.first(where: { $0.canControl && (known ? $0.passes(state) : $0.mark == .works) }), let via = way.via else {
                controls[app.id] = (known ? "No way worked in its check with its window \(state)." : "No way worked in every window state in its check.", false)
                return
            }
            control(app, action, via: via, note: known ? "Its window \(state): by \(AppDetail.wayName(via))." : nil)
        }
    }

    /// Plays or pauses it by that one way: playercheck --play or --pause
    /// --via `via` tries no other. `stopPress` ends it. `note` goes before
    /// what playercheck says (the window's state and the way chosen).
    func control(_ app: InstalledApp, _ action: String, via: String, note: String? = nil) {
        guard !isBusy, let tool else { return }
        let run: ToolRun
        do {
            run = try ToolRun(tool, [app.url.path, "--" + action, "--via", via])
        } catch {
            controls[app.id] = ("Couldn't run playercheck: \(error.localizedDescription)", false)
            return
        }
        controllingID = app.id
        controls[app.id] = ((action == "play" ? "Playing" : "Pausing") + "…", nil)
        pressProcess = run.process
        pressStopped = false
        Task {
            var output: [String] = []
            for await line in run.lines { output.append(line) }
            let status = await run.status()
            let said = output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            controls[app.id] = pressStopped
                ? ("Stopped before it said whether it worked.", false)
                : ((note.map { $0 + " " } ?? "") + said, status == 0)
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
            let (status, output) = await Task.detached { Self.runAndWait(tool, ["--launch-option", app.url.path]) }.value
            let parts = output.trimmingCharacters(in: .newlines).components(separatedBy: "\t")
            guard status == 0, parts.count == 2, !parts[0].isEmpty else {
                launchOptions[app.id] = nil
                return
            }
            launchOptions[app.id] = (parts[0], parts[1])
        }
    }

    /// Quits the app and opens it again with its launch option, in the
    /// background (playercheck --relaunch), then reads the option again.
    func relaunch(_ app: InstalledApp) {
        guard !isBusy, relaunchingID == nil, let tool else { return }
        relaunchingID = app.id
        relaunches[app.id] = nil
        Task {
            let (status, output) = await Task.detached { Self.runAndWait(tool, ["--relaunch", app.url.path]) }.value
            relaunches[app.id] = (output.trimmingCharacters(in: .whitespacesAndNewlines), status == 0)
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
        pressProcess.terminate()
    }

    /// When the app quits: stops what runs, so no playercheck goes on unwatched.
    func stopAll() {
        stop()
        stopPress()
    }

    /// Runs a tool to the end: its exit status and all it printed.
    nonisolated static func runAndWait(_ tool: URL, _ arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return (-1, "couldn't run \(tool.lastPathComponent)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// playercheck, built into this app's Resources by build.sh.
    let tool = Bundle.main.url(forResource: "playercheck", withExtension: nil)

    func scan() {
        isScanning = true
        let tool = self.tool
        Task {
            let found = await Task.detached { InstalledApp.scan(tool: tool) }.value
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
        let arguments = ["--now-playing-list"] + (since.map { ["--since", String($0.timeIntervalSince1970 - 2)] } ?? [])
        Task {
            let (status, output) = await Task.detached { Checker.runAndWait(tool, arguments) }.value
            if status == 0 {
                var updated = since == nil ? [:] : clients
                var active: String?
                for line in output.split(separator: "\n").map(String.init) {
                    if line.hasPrefix("#active\t") {
                        active = String(line.dropFirst("#active\t".count))
                    } else if let client = NowPlayingClient(line: line) {
                        if client.state == "Removed" {
                            if updated[client.bundleID]?.pid == client.pid { updated[client.bundleID] = nil }
                        } else if client.state == "Registered", updated[client.bundleID]?.pid == client.pid {
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
                // presses out of view (the user's choice, 2026-10-12).
                if app.hiddenInterface?.hasPrefix("Electron") == true {
                    let (_, said) = await Task.detached { Self.runAndWait(tool, ["--launch-option", app.url.path]) }.value
                    let option = said.components(separatedBy: "\t").first ?? ""
                    if !option.isEmpty { configuration.arguments = [option] }
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
    }

    private func run(_ tool: URL, on app: InstalledApp) async {
        let run: ToolRun
        do {
            run = try ToolRun(tool, [app.url.path])
        } catch {
            reports[app.id]?.state = .failed("Couldn't run playercheck: \(error.localizedDescription)")
            endAttempt(app.id)
            return
        }
        self.process = run.process
        let id = app.id
        for await line in run.lines where !line.isEmpty {
            reports[id]?.lines.append(line)
        }
        let status = await run.status()
        if reports[id]?.state == .checking {
            if status == 3 {
                // Cancelled before doing anything: a permission it needs isn't allowed.
                let lines = reports[id]?.lines ?? []
                let said = lines.last { $0.hasPrefix("Not checked: ") }.map { String($0.dropFirst("Not checked: ".count)) }
                    ?? "A permission the check needs isn't allowed."
                let missing = lines.first { $0.hasPrefix("  ") && ($0.hasSuffix(": not allowed") || $0.hasSuffix(": not answered")) }
                    .map { $0.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")[0] } ?? ""
                permissionProblems[id] = (said, missing)
                reports[id]?.state = .failed("The check was cancelled: \(said)")
            } else {
                reports[id]?.state = status == 0 ? .finished : .failed("playercheck ended with status \(status)")
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
            process.terminate()
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
        if let launch = checker.launchOptions[app.id], launch.running == "no" || checker.relaunchingID == app.id {
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
                    if app.isChromeWebApp { Tag(text: "Chrome web app", tint: .blue) }
                    if let interface = app.hiddenInterface { Tag(text: interface, tint: .purple) }
                }
                .padding(.top, 2)
            }
        }
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Privacy & Security at a permission's list, as playercheck names it
    /// ("System Audio Recording" is under Screen & System Audio Recording).
    static func openPrivacySettings(for permission: String) {
        let pane = permission == "Accessibility" ? "Privacy_Accessibility"
            : permission == "System Audio Recording" ? "Privacy_ScreenCapture"
            : permission.hasPrefix("Automation") ? "Privacy_Automation" : "Privacy"
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
                    Button("Open System Settings") { Self.openPrivacySettings(for: problem.missing) }
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
                Button { checker.controlByState(app, "play") } label: { Label("Play", systemImage: "play.fill") }
                Button { checker.controlByState(app, "pause") } label: { Label("Pause", systemImage: "pause.fill") }
            }
            .disabled(checker.isBusy || !running || checker.tool == nil)
            Text(!running ? "Open it first: it isn't running."
                 : "By the first way that worked in its check with its window as it is when pressed (covered, minimised, …).")
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

    static func wayName(_ via: String) -> String {
        switch via {
        case "script": "AppleScript"
        case "menu": "its playback menu"
        case "page": "its page's button"
        default: "its row in the Now Playing panel"
        }
    }

    private var confirmation: String {
        var parts: [String] = []
        if !checker.isTrusted {
            parts.append("It needs the Accessibility permission first: macOS asks for it, and the check starts once it's allowed.")
        }
        if !checker.isRunning(app) { parts.append("It isn't running: Player Check opens it first, in the background.") }
        parts.append("Before anything else, it makes sure Player Check has every permission a check needs: Accessibility, System Audio Recording, and Automation for \(app.name) if it can be scripted; macOS asks for any not decided yet, and without all of them the check is cancelled before it does anything.")
        parts.append("\(app.name) is muted all through the check (you won't hear it; Player Check still hears whether it plays) and heard again at the end.")
        parts.append("It reads its scripting dictionary, its menus, its sound and Now Playing, and its page's buttons if it shows a page.")
        parts.append("Before it moves anything, \(app.name) must be playing: if it isn't, you're asked to start it, and the check waits up to 2 minutes.")
        parts.append("Then it tests each way to control it: it pauses \(app.name) and plays it again by each, the menu bar's Now Playing panel included (it shows for a moment).")
        parts.append("It does so with \(app.name)'s window in each state: visible, covered (Player Check puts a window over it), on another desktop, covered there, full screen, minimised and hidden. Player Check moves the window there itself and comes back to the front each time; for the desktops it drags the window with the pointer and Control-arrow, so don't use the mouse or keyboard meanwhile. Player Check's own window may move aside. Everything is put back as it was at the end. It takes about 3 minutes.")
        if let launch = checker.launchOptions[app.id], launch.running == "no" {
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
                Text("Ways to control it").font(.headline)
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
    /// Plays ("play") or pauses ("pause") it this way; nil: no buttons.
    var control: ((String) -> Void)?
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
                Button { control("play") } label: { Image(systemName: "play.fill") }
                    .help("Play by \(name)").accessibilityLabel("Play by \(name)")
                Button { control("pause") } label: { Image(systemName: "pause.fill") }
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
        case .found: "questionmark.circle.fill"
        case .no: "xmark.circle.fill"
        case .notChecked: "minus.circle"
        }
    }
    private var tint: Color {
        switch way.mark {
        case .works: .green
        case .some: .orange
        case .found: .orange
        case .no: .red
        case .notChecked: .secondary
        }
    }
    private var label: String {
        switch way.mark {
        case .works: "Works"
        case .some: "Works in some states"
        case .found: "Found, not tried"
        case .no: "No"
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
                // Never full screen (the user, 2026-10-12: "The PlayerCheck
                // app should not be allowed to go full screen"). An AppKit
                // collection behavior set on the window didn't hold.
                .windowFullScreenBehavior(.disabled)
        }
        .defaultSize(width: 980, height: 680)
    }
}
