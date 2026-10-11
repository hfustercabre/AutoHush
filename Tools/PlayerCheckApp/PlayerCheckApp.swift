// Player Check: a window over Tools/PlayerCheck. It lists the apps in the
// Applications folders (/Applications, ~/Applications, /System/Applications,
// with their subfolders: Safari web apps included) that can be in macOS's
// Now Playing list, those macOS lists now first (playercheck's
// --now-playing-list, from macOS's log). Once an app is chosen and the check
// confirmed, it runs playercheck on it (opening it first when needed) and
// shows the ways it could be controlled, the verdict and the full report;
// checks are kept between launches. An app with a known way to control it
// (from its check, else from its bundle) gets Play and Pause buttons, and
// each way found gets its own (playercheck --play/--pause --via …).
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
    let electronVersion: String?
    /// Why it can be in Now Playing, from what it's built with; nil when
    /// nothing shows it can.
    let nowPlayingReason: String?
    /// Its scripting dictionary has play and pause commands.
    let scriptsPlayAndPause: Bool
    var id: String { url.path }

    /// How it could be played and paused before any check, from its bundle:
    /// AppleScript, or a page's button (a Safari web app, an Electron app).
    var controlHint: String? {
        if scriptsPlayAndPause { return "its scripting dictionary has play and pause" }
        if isSafariWebApp { return "a Safari web app: its page's buttons" }
        if electronVersion != nil { return "an Electron app: its page's buttons, with Electron's switch on" }
        return nil
    }

    /// Every .app in the Applications folders and their subfolders (not
    /// inside other apps), by name.
    static func scan() -> [InstalledApp] {
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
                let electron = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
                let electronVersion = FileManager.default.fileExists(atPath: electron.path)
                    ? (Bundle(url: electron)?.infoDictionary?["CFBundleVersion"] as? String ?? "?") : nil
                found.append(InstalledApp(url: url, name: name, bundleID: bundleID, root: root, subfolder: subfolder,
                                          isSafariWebApp: bundleID?.hasPrefix("com.apple.Safari.WebApp.") == true,
                                          isChromeWebApp: bundleID?.hasPrefix("com.google.Chrome.app.") == true,
                                          electronVersion: electronVersion,
                                          nowPlayingReason: nowPlayingReason(of: url, bundleID: bundleID),
                                          scriptsPlayAndPause: scriptsPlayAndPause(url)))
            }
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether its scripting dictionary (the .sdef its Info.plist names, read
    /// without running it) has commands called play and pause.
    static func scriptsPlayAndPause(_ url: URL) -> Bool {
        guard let bundle = Bundle(url: url),
              let name = bundle.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String,
              let file = bundle.url(forResource: name, withExtension: nil)
                ?? bundle.url(forResource: (name as NSString).deletingPathExtension, withExtension: "sdef"),
              let document = try? XMLDocument(contentsOf: file, options: [.nodeLoadExternalEntitiesNever])
        else { return false }
        let names = Set(((try? document.nodes(forXPath: "//command/@name")) ?? []).compactMap { $0.stringValue?.lowercased() })
        return names.contains("play") && names.contains("pause")
    }

    /// An app gets into Now Playing through MediaPlayer (MPNowPlayingInfoCenter
    /// and MPRemoteCommandCenter, the public way; Chromium and Electron use it
    /// too), MediaRemote (Apple's apps), AVKit's player view (a video it
    /// plays), or WebKit (Safari and its web apps, whose pages report through
    /// WebKit's media process). So: the frameworks its binaries link, those
    /// in Contents/MacOS (VLC's is a plugin there) and its own frameworks'.
    static func nowPlayingReason(of url: URL, bundleID: String?) -> String? {
        if bundleID?.hasPrefix("com.apple.Safari.WebApp.") == true { return "WebKit, as a Safari web app" }
        if bundleID == "com.apple.Safari" || bundleID?.hasPrefix("com.apple.SafariTechnologyPreview") == true { return "WebKit" }
        var binaries: [URL] = []
        let fileManager = FileManager.default
        if let items = fileManager.enumerator(at: url.appendingPathComponent("Contents/MacOS"), includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let item as URL in items where (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                binaries.append(item)
            }
        }
        let frameworks = url.appendingPathComponent("Contents/Frameworks")
        for framework in (try? fileManager.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)) ?? []
        where framework.pathExtension == "framework" {
            binaries.append(framework.appendingPathComponent(framework.deletingPathExtension().lastPathComponent))
        }
        var mediaPlayerIn: String?
        var others = Set<String>()
        for binary in binaries {
            let linked = MachO.frameworks(binary)
            if linked.contains("MediaPlayer"), mediaPlayerIn == nil { mediaPlayerIn = binary.lastPathComponent }
            others.formUnion(linked.intersection(["MediaRemote", "AVKit"]))
        }
        switch mediaPlayerIn {
        case "Electron Framework"?: return "MediaPlayer, through Electron"
        case "Chromium Embedded Framework"?: return "MediaPlayer, through Chromium (CEF)"
        case let name? where name.hasSuffix(" Framework"): return "MediaPlayer, through \(name)"
        case _?: return "MediaPlayer"
        case nil: break
        }
        if others.contains("MediaRemote") { return "MediaRemote" }
        if others.contains("AVKit") { return "AVKit, for videos it plays" }
        return nil
    }
}

/// Reads which frameworks a Mach-O file links, from its load commands.
enum MachO {
    /// "MediaPlayer" for /System/Library/Frameworks/MediaPlayer.framework/…,
    /// from the arm64 slice of a universal file (else its first); empty for
    /// a file that isn't 64-bit Mach-O.
    static func frameworks(_ url: URL) -> Set<String> {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        func read(_ offset: UInt64, _ count: Int) -> Data? {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.read(upToCount: count), data.count == count else { return nil }
            return data
        }
        guard let head = read(0, 8) else { return [] }
        var slice: UInt64 = 0
        switch head.word(0) {
        case 0xbeba_feca, 0xbfba_feca: // a universal file (FAT_MAGIC, FAT_MAGIC_64, big-endian)
            let wide = head.word(0) == 0xbfba_feca
            let count = Int(head.word(4, bigEndian: true)), size = wide ? 32 : 20
            guard (1...16).contains(count), let table = read(8, count * size) else { return [] }
            var chosen: UInt64?
            for index in 0..<count {
                let base = index * size
                let offset = wide ? UInt64(table.word(base + 8, bigEndian: true)) << 32 | UInt64(table.word(base + 12, bigEndian: true))
                                  : UInt64(table.word(base + 8, bigEndian: true))
                if table.word(base, bigEndian: true) == 0x0100_000c { chosen = offset; break } // arm64
                if chosen == nil { chosen = offset }
            }
            slice = chosen ?? 0
        case 0xfeed_facf: // MH_MAGIC_64
            break
        default:
            return []
        }
        guard let header = read(slice, 32), header.word(0) == 0xfeed_facf else { return [] }
        let commands = Int(header.word(16)), size = Int(header.word(20))
        guard size < 1 << 22, let table = read(slice + 32, size) else { return [] }
        // LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_LAZY_LOAD_DYLIB, LC_LOAD_UPWARD_DYLIB
        let linking: Set<UInt32> = [0xc, 0x8000_0018, 0x8000_001f, 0x20, 0x8000_0023]
        var names = Set<String>()
        var offset = 0
        for _ in 0..<commands {
            guard offset + 12 <= table.count else { break }
            let length = Int(table.word(offset + 4))
            guard length >= 12, offset + length <= table.count else { break }
            if linking.contains(table.word(offset)) {
                let start = offset + Int(table.word(offset + 8))
                if start < offset + length {
                    let path = String(decoding: table[start..<(offset + length)].prefix { $0 != 0 }, as: UTF8.self)
                    if let end = path.range(of: ".framework/"), let name = path[..<end.lowerBound].split(separator: "/").last {
                        names.insert(String(name))
                    }
                }
            }
            offset += length
        }
        return names
    }
}

extension Data {
    /// The 32-bit number at `offset` (Mach-O headers are little-endian, a
    /// universal file's table big-endian).
    func word(_ offset: Int, bigEndian: Bool = false) -> UInt32 {
        let value = withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        return bigEndian ? UInt32(bigEndian: value) : value
    }
}

// MARK: - macOS's own Now Playing list

/// An app mediaremoted keeps in Now Playing now, as `playercheck
/// --now-playing-list` reads it from macOS's log (administrators only).
struct NowPlayingClient {
    let bundleID: String
    /// Its last state (Playing, Paused, Stopped…), or Registered: ready for
    /// Now Playing, never said it plays.
    let state: String
    /// The one the Play/Pause key reaches.
    let isActive: Bool

    /// "<bundle ID>\t<pid>\t<state>\t<1 if active>\t<name>"
    init?(line: String) {
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 4 else { return nil }
        bundleID = parts[0]
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
    /// (only as Spotify's: VLC-like commands aren't used), the menu, the page,
    /// the Play/Pause key, the Now Playing panel.
    var via: String? {
        if title == "AppleScript", !detail.contains("not as Spotify") { return "script" }
        if title.hasPrefix("Playback menu") { return "menu" }
        if title.hasPrefix("Page button") { return "page" }
        if title == "Play/Pause key" { return "key" }
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
    var reports: [InstalledApp.ID: Report] = [:]
    var checkingID: InstalledApp.ID?
    var isTrusted = AXIsProcessTrusted()
    /// macOS's own Now Playing list, by bundle ID; why it couldn't be read.
    var clients: [String: NowPlayingClient] = [:]
    var clientsProblem: String?
    var isReadingClients = false
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
        /// The checks' kind: 2 from when every check tests every way. Older
        /// ones (nil) are dropped: their ✓ could mean "Now Playing now".
        var version: Int? = SavedReport.currentVersion
        static let currentVersion = 2
    }
    private static let savedReports = URL.applicationSupportDirectory.appending(path: "Player Check/reports.json")

    private func loadReports() {
        guard let data = try? Data(contentsOf: Self.savedReports),
              let saved = try? JSONDecoder().decode([String: SavedReport].self, from: data) else { return }
        reports = saved.filter { $0.value.version == SavedReport.currentVersion }
            .mapValues { Report(state: .finished, pressed: $0.pressed, lines: $0.lines, date: $0.date) }
    }

    private func saveReports() {
        let saved = reports.filter { $0.value.state == .finished }
            .mapValues { SavedReport(lines: $0.lines, pressed: $0.pressed, date: $0.date) }
        try? FileManager.default.createDirectory(at: Self.savedReports.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: Self.savedReports)
    }

    // MARK: Playing and pausing

    /// Whether a way to play and pause it is known: from its finished check,
    /// else from its bundle.
    func canControl(_ app: InstalledApp) -> Bool {
        if let report = reports[app.id], report.state == .finished { return report.ways.contains(where: \.canControl) }
        return app.controlHint != nil
    }

    /// The way its Play and Pause buttons use: the first that worked in its
    /// check. Nil when none did: playercheck then tries AppleScript, the
    /// page's button and the menu in turn (a menu found may be ignored, as
    /// Deezer's is: picking it alone would fail where the page works).
    func preferredWay(_ app: InstalledApp) -> Way? {
        guard let report = reports[app.id], report.state == .finished else { return nil }
        return report.ways.first { $0.canControl && $0.mark == .works }
    }

    /// Plays or pauses it: playercheck --play or --pause, by `via` or the
    /// first way that works.
    func control(_ app: InstalledApp, _ action: String, via: String?) {
        guard !isBusy, let tool else { return }
        controllingID = app.id
        controls[app.id] = ((action == "play" ? "Playing" : "Pausing") + "…", nil)
        let arguments = [app.url.path, "--" + action] + (via.map { ["--via", $0] } ?? [])
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
        Task {
            let found = await Task.detached { InstalledApp.scan() }.value
            apps = found
            isScanning = false
        }
        refreshRunning()
        readClients()
    }

    /// Reads macOS's Now Playing list again (a few seconds: it reads the log
    /// since the Mac started).
    func readClients() {
        guard !isReadingClients, let tool else {
            if tool == nil { clientsProblem = "playercheck is missing from this app: build it with build.sh." }
            return
        }
        isReadingClients = true
        Task {
            let (status, output) = await Task.detached { Checker.runAndWait(tool, ["--now-playing-list"]) }.value
            if status == 0 {
                clients = Dictionary(output.split(separator: "\n").compactMap { NowPlayingClient(line: String($0)) }
                    .map { ($0.bundleID, $0) }, uniquingKeysWith: { first, second in first.isActive ? first : second })
                clientsProblem = nil
            } else {
                clients = [:]
                clientsProblem = "macOS's own Now Playing list couldn't be read: "
                    + output.trimmingCharacters(in: .whitespacesAndNewlines) + " (it needs an administrator account)."
            }
            isReadingClients = false
        }
    }

    func client(of app: InstalledApp) -> NowPlayingClient? {
        app.bundleID.flatMap { clients[$0] }
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
        checkingID = app.id
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
                    reports[app.id]?.state = .failed("Couldn't open it: \(error.localizedDescription)")
                    checkingID = nil
                    return
                }
                guard reports[app.id]?.state == .opening else { return } // stopped meanwhile
                reports[app.id]?.state = .checking
                refreshRunning()
            }
            await run(tool, on: app)
        }
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
            checkingID = nil
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
        saveReports()
        self.process = nil
        checkingID = nil
        refreshRunning()
        readClients()
    }

    /// Stops the check: playercheck sets Electron's switch back first.
    func stop() {
        guard let id = checkingID else { return }
        reports[id]?.state = .stopped
        if let process {
            process.terminate()
        } else {
            checkingID = nil
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
                                   isChecked: checker.reports[app.id]?.state == .finished).tag(app.id)
                        }
                    }
                }
                ForEach(InstalledApp.Root.allCases, id: \.self) { root in
                    let apps = shown.filter { $0.root == root && checker.client(of: $0) == nil }
                    if !apps.isEmpty {
                        Section(root.title) {
                            ForEach(apps) { app in
                                AppRow(app: app, isRunning: checker.isRunning(app), client: nil,
                                       isChecked: checker.reports[app.id]?.state == .finished).tag(app.id)
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
                if checker.canControl(app) { playAndPause }
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
                    if let version = app.electronVersion { Tag(text: "Electron \(version)", tint: .purple) }
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

    /// Play and Pause, by the way its check found (or each in turn).
    private var playAndPause: some View {
        let way = checker.preferredWay(app)
        let running = checker.isRunning(app)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Play and Pause").font(.headline)
            HStack {
                Button { checker.control(app, "play", via: way?.via) } label: { Label("Play", systemImage: "play.fill") }
                Button { checker.control(app, "pause", via: way?.via) } label: { Label("Pause", systemImage: "pause.fill") }
                if checker.controllingID == app.id { ProgressView().controlSize(.small) }
            }
            .disabled(checker.isBusy || !running || checker.tool == nil)
            Text(!running ? "Open it first: it isn't running."
                 : way.map { "By \(Self.wayName($0.via)), which worked in its check." }
                    ?? (checker.reports[app.id]?.state == .finished
                        ? "None worked in its check yet (found, not tried): it tries AppleScript, its page's button, then its menu."
                        : "Not checked yet (\(app.controlHint ?? "")): it tries AppleScript, its page's button, then its menu."))
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

    static func wayName(_ via: String?) -> String {
        switch via {
        case "script": "AppleScript"
        case "menu": "its playback menu"
        case "page": "its page's button"
        case "key": "the Play/Pause key"
        case "panel": "its row in the Now Playing panel"
        default: "the first way that works"
        }
    }

    private var confirmation: String {
        var parts: [String] = []
        if !checker.isRunning(app) { parts.append("It isn't running: Player Check opens it first, in the background.") }
        parts.append("It reads its scripting dictionary, its menus, its sound and Now Playing"
            + (app.isSafariWebApp || app.electronVersion != nil ? ", and its page's buttons." : "."))
        parts.append("Then it tests each way to control it: it pauses \(app.name) and plays it again by each, the Play/Pause key and the menu bar's Now Playing panel included (it shows for a moment). If \(app.name) isn't playing, you're asked to start it.")
        if app.electronVersion != nil { parts.append("Electron's accessibility switch is turned on for the check, and back off after.") }
        return parts.joined(separator: " ")
    }

    @ViewBuilder private func results(_ report: Report) -> some View {
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
                    WayRow(way: way, control: way.canControl && checker.isRunning(app) && report.state == .finished
                        ? { checker.control(app, $0, via: way.via) } : nil,
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
            if let control {
                let name = AppDetail.wayName(way.via)
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
