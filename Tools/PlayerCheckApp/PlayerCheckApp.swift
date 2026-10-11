// Player Check: a window over Tools/PlayerCheck. It lists the apps in the
// Applications folders (/Applications, ~/Applications, /System/Applications,
// with their subfolders: Safari web apps included) that can be in macOS's
// Now Playing list, those macOS lists now first (playercheck's
// --now-playing-list, from macOS's log). Once an app is chosen and the check
// confirmed, it runs playercheck on it (opening it first when needed) and
// shows the ways it could be controlled, the verdict and the full report;
// checks are kept between launches. An app whose check found a way that
// works gets Play and Pause buttons, by the first such way, and each way
// found gets its own (playercheck --play/--pause --via …).
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
    /// "Flutter" (as playercheck tells them).
    let hiddenInterface: String?
    /// Why it can be in Now Playing, from what it's built with; nil when
    /// nothing shows it can (playercheck --now-playing-reasons).
    let nowPlayingReason: String?
    var id: String { url.path }

    /// The switches playercheck turns on to read its interface: Electron's
    /// (AXManualAccessibility), VoiceOver's (AXEnhancedUserInterface) or
    /// both, tried in that order.
    var switchNote: String? {
        guard let hiddenInterface else { return nil }
        let which = hiddenInterface.hasPrefix("Electron") ? "Electron's accessibility switch is"
            : hiddenInterface == "Flutter" ? "VoiceOver's accessibility switch is"
            : "Electron's accessibility switch, else VoiceOver's, is"
        return "\(which) turned on for the check, and back off after."
    }

    /// Electron, Chromium (CEF) or Flutter, by the framework in its bundle.
    static func hiddenInterface(_ url: URL) -> String? {
        let frameworks = url.appendingPathComponent("Contents/Frameworks")
        let electron = frameworks.appendingPathComponent("Electron Framework.framework")
        if FileManager.default.fileExists(atPath: electron.path) {
            return "Electron " + (Bundle(url: electron)?.infoDictionary?["CFBundleVersion"] as? String ?? "?")
        }
        if FileManager.default.fileExists(atPath: frameworks.appendingPathComponent("Chromium Embedded Framework.framework").path) {
            return "Chromium (CEF)"
        }
        if FileManager.default.fileExists(atPath: frameworks.appendingPathComponent("FlutterMacOS.framework").path) { return "Flutter" }
        return nil
    }

    /// Every .app in the Applications folders and their subfolders (not
    /// inside other apps), by name. Why each can be in Now Playing comes from
    /// `tool` (playercheck), asked once for them all.
    static func scan(tool: URL?) -> [InstalledApp] {
        var found: [InstalledApp] = []
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
                found.append(InstalledApp(url: url, name: name, bundleID: bundleID, root: root, subfolder: subfolder,
                                          isSafariWebApp: bundleID?.hasPrefix("com.apple.Safari.WebApp.") == true,
                                          isChromeWebApp: bundleID?.hasPrefix("com.google.Chrome.app.") == true,
                                          hiddenInterface: hiddenInterface(url), nowPlayingReason: nil))
            }
        }
        var reasons: [String: String] = [:]
        if let tool, !found.isEmpty {
            let (status, output) = Checker.runAndWait(tool, ["--now-playing-reasons"] + found.map(\.url.path))
            if status == 0 {
                for line in output.split(separator: "\n") {
                    let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                    if parts.count == 2 { reasons[parts[0]] = parts[1] }
                }
            }
        }
        return found.map { app in
            InstalledApp(url: app.url, name: app.name, bundleID: app.bundleID, root: app.root, subfolder: app.subfolder,
                         isSafariWebApp: app.isSafariWebApp, isChromeWebApp: app.isChromeWebApp,
                         hiddenInterface: app.hiddenInterface, nowPlayingReason: reasons[app.url.path])
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

/// One line of playercheck's "Ways to control it".
struct Way: Identifiable {
    enum Mark { case works, found, no, notChecked }
    let id: Int
    let mark: Mark
    let title: String
    let detail: String

    /// "  ✓ AppleScript: pausing … worked" → works, "AppleScript", "pausing … worked".
    init?(id: Int, line: String) {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return nil }
        switch first {
        case "✓": mark = .works
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
    /// A way to play and pause with: it worked in the check, or was found.
    var canControl: Bool { via != nil && (mark == .works || mark == .found) }
}

/// What playercheck said about one app, as it comes in.
struct Report {
    enum State: Equatable { case opening, checking, finished, stopped, failed(String) }
    var state: State
    let pressed: Bool
    var lines: [String] = []
    var date = Date()

    /// The lines under a heading (a line that isn't indented).
    func section(_ title: String) -> [String] {
        guard let start = lines.firstIndex(of: title) else { return [] }
        return Array(lines[(start + 1)...].prefix { $0.hasPrefix(" ") })
    }
    var ways: [Way] { section("Ways to control it").enumerated().compactMap { Way(id: $0.offset, line: $0.element) } }
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
    private var process: Process?

    /// A check or a Play/Pause is running: one at a time.
    var isBusy: Bool { checkingID != nil || controllingID != nil }

    init() {
        loadReports()
    }

    // MARK: Checks kept between launches

    private struct SavedReport: Codable {
        let lines: [String]
        let pressed: Bool
        let date: Date
        /// The checks' kind: 3 from when the Play/Pause key stopped being a
        /// way (it reaches only the Now Playing app, which AutoHush can't
        /// choose). Older ones are dropped: they list it.
        var version: Int? = SavedReport.currentVersion
        static let currentVersion = 3
    }
    private static let savedReports = URL.applicationSupportDirectory.appending(path: "Player Check/reports.json")

    private func loadReports() {
        guard let data = try? Data(contentsOf: Self.savedReports),
              let saved = try? JSONDecoder().decode([String: SavedReport].self, from: data) else { return }
        finished = saved.filter { $0.value.version == SavedReport.currentVersion }
            .mapValues { Report(state: .finished, pressed: $0.pressed, lines: $0.lines, date: $0.date) }
        reports = finished
    }

    private func saveReports() {
        let saved = finished.mapValues { SavedReport(lines: $0.lines, pressed: $0.pressed, date: $0.date) }
        try? FileManager.default.createDirectory(at: Self.savedReports.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: Self.savedReports)
    }

    // MARK: Playing and pausing

    /// The way its Play and Pause buttons use: the first in the list that
    /// worked (✓) in its last finished check. Nil before a check, or when none
    /// worked: then there are no such buttons.
    func preferredWay(_ app: InstalledApp) -> Way? {
        finished[app.id]?.ways.first { $0.canControl && $0.mark == .works }
    }

    /// Plays or pauses it by that one way: playercheck --play or --pause
    /// --via `via` tries no other.
    func control(_ app: InstalledApp, _ action: String, via: String) {
        guard !isBusy, let tool else { return }
        controllingID = app.id
        controls[app.id] = ((action == "play" ? "Playing" : "Pausing") + "…", nil)
        let arguments = [app.url.path, "--" + action, "--via", via]
        Task {
            let (status, output) = await Task.detached { Checker.runAndWait(tool, arguments) }.value
            controls[app.id] = (output.trimmingCharacters(in: .whitespacesAndNewlines), status == 0)
            controllingID = nil
            readClients()
        }
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

    /// Opens the app when it isn't running (and gives it time to load its
    /// window and page), then runs playercheck on it.
    func check(_ app: InstalledApp) {
        guard !isBusy, let tool else { return }
        let token = UUID()
        attempt = token
        checkingID = app.id
        attemptNotes[app.id] = nil
        let opening = !isRunning(app)
        reports[app.id] = Report(state: opening ? .opening : .checking, pressed: true)
        Task {
            if opening {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
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
        let process = Process()
        process.executableURL = tool
        process.arguments = [app.url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            reports[app.id]?.state = .failed("Couldn't run playercheck: \(error.localizedDescription)")
            endAttempt(app.id)
            return
        }
        self.process = process
        let id = app.id
        let handle = pipe.fileHandleForReading
        let lines = AsyncStream<String> { continuation in
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
        for await line in lines where !line.isEmpty {
            reports[id]?.lines.append(line)
        }
        process.waitUntilExit()
        if reports[id]?.state == .checking {
            reports[id]?.state = process.terminationStatus == 0 ? .finished
                : .failed("playercheck ended with status \(process.terminationStatus)")
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
    @State private var checker = Checker()
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            checker.stop()
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
    @State private var showsReport = false

    private var report: Report? { checker.reports[app.id] }
    private var isChecking: Bool { checker.checkingID == app.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !checker.isTrusted { permissionNote }
                controls
                if let way = checker.preferredWay(app), let via = way.via { playAndPause(via: via) }
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

    private var permissionNote: some View {
        GroupBox {
            HStack {
                Label("Player Check needs the Accessibility permission to read menus and pages.", systemImage: "exclamationmark.triangle")
                Spacer()
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
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
                    Text(report?.state == .opening ? "Opening \(app.name)…" : report?.request != nil ? "Waiting for you…" : "Checking…")
                        .foregroundStyle(.secondary)
                }
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
            if checker.tool == nil {
                Text("playercheck is missing from this app: build it with build.sh.").foregroundStyle(.red)
            }
        }
    }

    /// Play and Pause, by the first way that worked in its check, alone.
    private func playAndPause(via: String) -> some View {
        let running = checker.isRunning(app)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Play and Pause").font(.headline)
            HStack {
                Button { checker.control(app, "play", via: via) } label: { Label("Play", systemImage: "play.fill") }
                Button { checker.control(app, "pause", via: via) } label: { Label("Pause", systemImage: "pause.fill") }
                if checker.controllingID == app.id { ProgressView().controlSize(.small) }
            }
            .disabled(checker.isBusy || !running || checker.tool == nil)
            Text(!running ? "Open it first: it isn't running."
                 : "By \(Self.wayName(via)), the first way that worked in its check.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let result = checker.controls[app.id], let worked = result.worked {
                Label(result.text, systemImage: worked ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(worked ? .green : .red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        if !checker.isRunning(app) { parts.append("It isn't running: Player Check opens it first, in the background.") }
        parts.append("It reads its scripting dictionary, its menus, its sound and Now Playing, and its page's buttons if it shows a page.")
        parts.append("Then it tests each way to control it: it pauses \(app.name) and plays it again by each, the menu bar's Now Playing panel included (it shows for a moment). If \(app.name) isn't playing, you're asked to start it.")
        if let note = app.switchNote { parts.append(note) }
        return parts.joined(separator: " ")
    }

    @ViewBuilder private func results(_ report: Report) -> some View {
        if let note = checker.attemptNotes[app.id] {
            Label(note, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
        }
        if case .failed(let reason) = report.state {
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
                Text("✓ worked in the test  ·  ✗ not there or didn't work  ·  ? not tried  ·  – not checked")
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
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(way.title). \(way.detail)")
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
        case .found: "questionmark.circle.fill"
        case .no: "xmark.circle.fill"
        case .notChecked: "minus.circle"
        }
    }
    private var tint: Color {
        switch way.mark {
        case .works: .green
        case .found: .orange
        case .no: .red
        case .notChecked: .secondary
        }
    }
    private var label: String {
        switch way.mark {
        case .works: "Works"
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct PlayerCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Player Check", id: "main") {
            ContentView()
        }
        .defaultSize(width: 980, height: 680)
    }
}
