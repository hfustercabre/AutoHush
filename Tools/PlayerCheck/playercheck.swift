// playercheck: could AutoHush control this app as a player, and how? It
// reads the app's scripting dictionary, its playback menu, where its sound
// comes from, whether it holds Now Playing and the buttons of its page (a
// web page in its windows, a Safari web app's or any app's; an Electron or
// CEF app's, or a Flutter app's interface, once a switch for assistive tools
// is on), then lists the ways it could be controlled and says which kind of
// player it could be (as in the adding-a-player skill's first table).
// Tools/PlayerCheckApp runs it from a window.
//   playercheck <app name, bundle ID or path>          checks it, and tests each way to control it: pauses
//                                                      and plays it once by each (asking for it to be
//                                                      started first when it isn't playing)
//   playercheck <app> --read-only                      checks it without pressing anything
//   playercheck <app> --play|--pause [--via script|menu|page|panel]
//                                                      just plays or pauses it, by that way (reading only what it
//                                                      needs) or the first that works
//   playercheck --now-playing-list [hours]             the apps macOS keeps in Now Playing, from its log
//                                                      (administrators only): "<bundle ID>\t<pid>\t<state>\t<1 if active>\t<name>",
//                                                      then "#active\t<pid>"
//   playercheck --now-playing-list --since <unix time> what changed since then, apps gone as "Removed"
//   playercheck --now-playing-reasons <app path>…      why each app can be in Now Playing, as Player Check lists them:
//                                                      "<path>\t<reason>\t<framework>\t<switches>" (each empty when none)
// Each check or press is also logged in ~/Library/Logs/PlayerCheck (the last 50).
// A target of AutoHush's package, using AutoHush's own code wherever the two
// do the same thing (Apple events, menus, learned page buttons, sound).
// Build: swift build -c release --product playercheck
import AppKit
import ApplicationServices
import AutoHushKit
import CoreAudio
import MenuPlayers
import OSLog
import ScriptablePlayers
import VLCSupport
import WebAppPlayers

// MARK: - Output

/// Set for --play and --pause: the checks run silently, then one line says what was done.
var quiet = false
func say(_ line: String = "") {
    log(line)
    guard !quiet else { return }
    print(line)
    fflush(stdout)
}
func fail(_ line: String) -> Never {
    log("playercheck: \(line)")
    FileHandle.standardError.write(Data("playercheck: \(line)\n".utf8))
    exit(1)
}

/// Each check or press of an app is also written, whole (the quiet parts of
/// a press too) and with each line's time, to a file of its own in
/// ~/Library/Logs/PlayerCheck, the last `logsKept` kept: a run whose result
/// went wrong can be read afterwards, though a later check replaced it in
/// Player Check (the user's first check of Deezer, 2026-10-11).
let logsFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PlayerCheck")
let logsKept = 50
var logFile: FileHandle?
let logTime: DateFormatter = {
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.dateFormat = "HH:mm:ss.SSS"
    return format
}()
func log(_ line: String) {
    logFile?.write(Data("\(logTime.string(from: Date()))  \(line)\n".utf8))
}

/// Starts this run's log, named by its time, the app and what it does,
/// and removes the oldest beyond `logsKept` (files this tool wrote).
func startLog(app: String, doing: String) {
    let files = FileManager.default
    try? files.createDirectory(at: logsFolder, withIntermediateDirectories: true)
    let name = DateFormatter()
    name.locale = Locale(identifier: "en_US_POSIX")
    name.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
    let safe = { (text: String) in text.map { "/:".contains($0) ? "-" : String($0) }.joined() }
    let url = logsFolder.appendingPathComponent("\(name.string(from: Date())) \(safe(app)) \(safe(doing)).log")
    guard files.createFile(atPath: url.path, contents: nil), let handle = try? FileHandle(forWritingTo: url) else { return }
    logFile = handle
    let os = ProcessInfo.processInfo.operatingSystemVersion
    log("playercheck " + CommandLine.arguments.dropFirst().joined(separator: " ")
        + "  (pid \(getpid()), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), "
        + (ProcessInfo.processInfo.environment["__CFBundleIdentifier"].map { "run by \($0)" } ?? "run from a shell") + ")")
    let logs = ((try? files.contentsOfDirectory(atPath: logsFolder.path)) ?? []).filter { $0.hasSuffix(".log") }.sorted()
    for old in logs.dropLast(logsKept) { try? files.removeItem(at: logsFolder.appendingPathComponent(old)) }
}
atexit { log("(ended)") }
// Whoever reads the output may go first (Player Check quitting mid-check):
// writing then fails quietly, and a test that paused the app still plays
// it again and puts back what it changed, instead of being killed.
signal(SIGPIPE, SIG_IGN)

// MARK: - Now Playing (MediaRemote, read only)

/// The process in Now Playing, 0 for none, -1 when MediaRemote doesn't
/// answer, as AutoHush asks it (`NowPlayingApp`): a process asks MediaRemote
/// once and keeps its first answer, so each question runs a fresh copy of
/// this tool (with `NowPlayingApp.argument`).
func nowPlayingPID() -> pid_t {
    // This tool's own path: inside the Player Check app, Bundle.main is the app's.
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let own = URL(fileURLWithPath: proc_pidpath(getpid(), &path, UInt32(path.count)) > 0 ? String(cString: path) : CommandLine.arguments[0])
    switch NowPlayingApp.current(executable: own) {
    case .process(let pid): return pid
    case .none: return 0
    case .unknown: return -1
    }
}

if CommandLine.arguments.dropFirst().first == NowPlayingApp.argument {
    NowPlayingApp.printAnswer()
    exit(0)
}

// MARK: - The apps in Now Playing (--now-playing-list)

/// One app mediaremoted keeps for Now Playing, as its log names it:
/// "com.spotify.client (380) Spotify", or for a web app
/// "com.apple.WebKit.GPU/com.apple.Safari.WebApp.<UUID> (723) YT Music",
/// WebKit's media process on the web app's behalf.
struct NowPlayingClient {
    var id: String
    let pid: pid_t
    /// As the log names it ("Creating nowPlayingClient" lines don't).
    var name = ""
    /// Its last PlaybackState (Playing, Paused, Stopped…); nil while it never reported one.
    var state: String?
    /// When it reported that state.
    var changed: Date?
    var removed = false
    /// The app's own bundle ID (a web app's, not WebKit's).
    var appID: String { id.split(separator: "/").last.map(String.init) ?? id }
    var displayName: String {
        if !name.isEmpty { return name }
        let app = id.contains("/") ? NSRunningApplication.runningApplications(withBundleIdentifier: appID).first
                                   : NSRunningApplication(processIdentifier: pid)
        return app?.localizedName ?? appID
    }
}

// The client: "<bundle ID>[/<bundle ID>] (<pid>) <name>", ending at ❯, 】, 〗 or "for".
let clientPattern = try! NSRegularExpression(pattern: #"([A-Za-z0-9.\-]+(?:/[A-Za-z0-9.\-]+)?) \((\d+)\) (.*?)\s*(?:❯|】|〗| for |$)"#)
let statePattern = try! NSRegularExpression(pattern: #"PlaybackState changed from (\w+) to (\w+)"#)

/// Reads what MediaRemote's daemon wrote in macOS's log from `start` into
/// `clients`, by process: each client it creates and removes, and each
/// one's "PlaybackState changed from … to …". False when the log can't be
/// read from there. WebKit's media process is created under its own ID,
/// then plays as "com.apple.WebKit.GPU/<the web app's ID>".
func readNowPlayingLog(_ store: OSLogStore, from start: Date, into clients: inout [pid_t: NowPlayingClient]) -> Bool {
    let predicate = NSPredicate(format: "process == %@ AND (composedMessage CONTAINS %@ OR composedMessage CONTAINS %@)",
                                "mediaremoted", "nowPlayingClient", "PlaybackState changed")
    guard let entries = try? store.getEntries(at: store.position(date: start), matching: predicate) else { return false }
    for case let entry as OSLogEntryLog in entries { applyNowPlayingLine(entry.composedMessage, at: entry.date, to: &clients) }
    return true
}

/// One of those lines, applied to the client it names.
func applyNowPlayingLine(_ message: String, at date: Date, to clients: inout [pid_t: NowPlayingClient]) {
    func group(_ match: NSTextCheckingResult, _ index: Int) -> String {
        Range(match.range(at: index), in: message).map { String(message[$0]) } ?? ""
    }
    let whole = NSRange(message.startIndex..., in: message)
    guard let match = clientPattern.firstMatch(in: message, range: whole), let pid = pid_t(group(match, 2)) else { return }
    let id = group(match, 1)
    var client = clients[pid] ?? NowPlayingClient(id: id, pid: pid)
    if id.count > client.id.count { client.id = id }
    let name = group(match, 3)
    if !name.isEmpty { client.name = name }
    if message.contains("Removing nowPlayingClient") {
        client.removed = true
    } else if message.contains("Creating nowPlayingClient") {
        client.removed = false
    } else if let state = statePattern.firstMatch(in: message, range: whole) {
        client.state = group(state, 2)
        client.changed = date
    }
    clients[pid] = client
}

/// The apps macOS keeps in Now Playing, one tab-separated line each:
/// bundle ID, process, last state (or Registered: ready for Now Playing,
/// never said it plays), 1 for the active one (the Now Playing app), name.
/// Unentitled apps can't ask MediaRemote for that list (since macOS 15.4),
/// so it's read from what MediaRemote's daemon writes in macOS's log since
/// the Mac started (or the last `hours`): each client it creates, each
/// one's "PlaybackState changed from … to …" (also while another app is the
/// active one), and those it removes when they quit. Reading the log needs
/// an administrator; its wording is macOS's, not an API (checked on macOS 27).
func printNowPlayingList() -> Never {
    var boot = timeval()
    var size = MemoryLayout<timeval>.size
    sysctlbyname("kern.boottime", &boot, &size, nil, 0)
    let rest = Array(CommandLine.arguments.dropFirst(2))
    // --since: only what changed since then (a caller that read the whole list
    // before keeps it up to date this way, without reading days of log again).
    let since = rest.firstIndex(of: "--since").flatMap { $0 + 1 < rest.count ? Double(rest[$0 + 1]) : nil }
    let start = since.map { Date(timeIntervalSince1970: $0) }
        ?? rest.first.flatMap(Double.init).map { Date().addingTimeInterval(-$0 * 3600) }
        ?? Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    let store: OSLogStore
    do { store = try OSLogStore.local() } catch {
        print("can't read macOS's log: \(error.localizedDescription)")
        exit(1)
    }
    var clients: [pid_t: NowPlayingClient] = [:]
    guard readNowPlayingLog(store, from: start, into: &clients) else {
        print("can't read macOS's log from \(start)")
        exit(1)
    }
    let active = nowPlayingPID()
    // Still there: not removed, and its process still runs. With --since, the
    // ones gone meanwhile too, as Removed.
    for client in clients.values {
        let there = !client.removed && (kill(client.pid, 0) == 0 || errno == EPERM)
        guard there || since != nil else { continue }
        print([client.appID, "\(client.pid)", there ? client.state ?? "Registered" : "Removed", client.pid == active ? "1" : "0",
               client.displayName].joined(separator: "\t"))
    }
    print("#active\t\(active)")
    exit(0)
}

if CommandLine.arguments.dropFirst().first == "--now-playing-list" { printNowPlayingList() }

/// --now-playing-reasons <app path>…: for the Player Check app's list, a
/// line per app, "<path>\t<why it can be in Now Playing, or nothing>\t<the
/// framework that hides its interface, or nothing>\t<the switches a check
/// turns on for it, in order>", so the window shows this tool's own rule.
if CommandLine.arguments.dropFirst().first == "--now-playing-reasons" {
    for path in CommandLine.arguments.dropFirst(2) {
        let url = URL(fileURLWithPath: path)
        let hidden = HiddenInterface.of(url)
        print([path, nowPlayingReason(of: url, bundleID: Bundle(url: url)?.bundleIdentifier) ?? "", hidden?.name ?? "",
               hidden?.switches.map(switchName).joined(separator: ", else ") ?? ""].joined(separator: "\t"))
    }
    exit(0)
}

// MARK: - The app

let arguments = Array(CommandLine.arguments.dropFirst())
guard let target = arguments.first(where: { !$0.hasPrefix("--") }) else {
    fail("usage: playercheck <app name, bundle ID or path> [--read-only | --play | --pause [--via script|menu|page|panel]]")
}
/// --read-only: the checks without the test.
let readOnly = arguments.contains("--read-only")
/// --play or --pause: does just that, by `via` (script, menu, page or
/// panel), else by the first way that works: AppleScript, the page's button,
/// the menu.
let action = arguments.contains("--play") ? "play" : arguments.contains("--pause") ? "pause" : nil
let via = arguments.firstIndex(of: "--via").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
quiet = action != nil
/// The test: each way to control it is tried, pausing it and playing it again.
let testing = !readOnly && action == nil
/// --play or --pause by one way: only what that way needs is read, and what
/// shows whether the app plays (`isPlaying`), so a press starts sooner.
let pressingOneWay = action != nil && via != nil

/// The app's bundle: a path, a bundle ID, or a name in the Applications folders.
func findApp(_ target: String) -> URL? {
    // A path only when it looks like one: "Music" is also the ~/Music folder.
    if target.contains("/") || target.hasSuffix(".app"), FileManager.default.fileExists(atPath: target) {
        return URL(fileURLWithPath: target)
    }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) { return url }
    let name = target.hasSuffix(".app") ? target : target + ".app"
    let folders = ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications",
                   "/System/Applications/Utilities", "/Applications/Utilities"]
    for folder in folders where FileManager.default.fileExists(atPath: folder + "/" + name) {
        return URL(fileURLWithPath: folder + "/" + name)
    }
    return NSWorkspace.shared.runningApplications.first { $0.localizedName == target }?.bundleURL
}

guard let appURL = findApp(target), let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier else {
    fail("no app found for \(target)")
}
let info = bundle.infoDictionary ?? [:]
let appName = (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String ?? appURL.deletingPathExtension().lastPathComponent
let version = info["CFBundleShortVersionString"] as? String ?? "?"
let isWebApp = bundleID.hasPrefix("com.apple.Safari.WebApp.")
var running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first

startLog(app: appName, doing: action.map { $0 + (via.map { " via \($0)" } ?? "") } ?? (readOnly ? "read-only" : "check"))
say("\(appName) \(version) (\(bundleID))")
say("  \(appURL.path)")
say("  " + (running.map { "running, pid \($0.processIdentifier)" } ?? "not running: the menu, sound and Now Playing checks need it running"))

// MARK: - Scripting dictionary

/// What AutoHush's ScriptablePlayers need: pause and play in the app's own
/// suite (`<suite>Paus`, `<suite>Play`), the `player state` property (pPlS)
/// with stopped/playing/paused (kPSS, kPSP, kPSp), and `sound volume` (pVol)
/// for fades.
struct Scripting {
    var commands: [String: String] = [:]   // code → name
    /// The application's own properties: an app's state is read there only
    /// (QuickTime Player's `playing` is each document's, not the app's).
    var properties: [String: String] = [:]
    var enumerators: Set<String> = []
    /// The commands that must be told which document to act on (QuickTime
    /// Player's play and pause: "play document 1"), by code.
    var documentCommands: Set<String> = []
    /// The document class's code, and its `playing` property's (QuickTime
    /// Player: "docu", "play").
    var documentClass: String?
    var documentPlaying: String?

    var suite: String? {
        let pauses = Set(commands.keys.filter { $0.hasSuffix("Paus") }.map { String($0.prefix(4)) })
        let plays = Set(commands.keys.filter { $0.hasSuffix("Play") }.map { String($0.prefix(4)) })
        return pauses.intersection(plays).sorted().first
    }
    var hasPlayerState: Bool { properties["pPlS"] != nil }
    /// A true/false `playing` property instead (VLC's): its state too.
    var hasPlayingFlag: Bool { properties.values.contains("playing") }
    var hasStateValues: Bool { enumerators.isSuperset(of: ["kPSS", "kPSP", "kPSp"]) }
    /// Played and paused through its documents, each with its own `playing`
    /// (QuickTime Player): it plays while one does.
    var playsDocuments: Bool {
        documentClass != nil && documentPlaying != nil
            && ["pause", "play"].allSatisfy { commandCode($0).map(documentCommands.contains) == true }
    }
    /// Whether its state can be read by script: `player state`, a `playing`
    /// flag, or its documents'.
    var hasState: Bool { hasPlayerState || hasPlayingFlag || playsDocuments }
    var hasVolume: Bool { properties["pVol"] != nil }
    /// A `current track` (pTrk) with a name: what it plays, by script.
    var hasCurrentTrack: Bool { properties["pTrk"] != nil }
    var fitsScriptablePlayer: Bool { suite != nil && hasPlayerState && hasStateValues }
    /// A command's code ("spfyPaus") by its name: the app's own suite's
    /// first, as ScriptablePlayers sends it.
    func commandCode(_ name: String) -> String? {
        let codes = commands.filter { $0.value.lowercased() == name.lowercased() }.keys.sorted()
        return codes.first { $0.hasPrefix(suite ?? "????") } ?? codes.first
    }
}

/// Why the dictionary wasn't read, when it wasn't.
var scriptingNote: String?

/// The app's dictionary: the .sdef its Info.plist names, else one in its
/// resources, read as it is (running `sdef` takes about 0.15 s); else as
/// `sdef` prints it, from an aete or old .scriptSuite files, but only while
/// the app runs: `sdef` opens an app to ask it, and this tool never launches
/// one, as AutoHush never does. `nil` when it has none.
func readScripting(_ url: URL) -> Scripting? {
    let bundle = Bundle(url: url)
    let named = (bundle?.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String).flatMap { name in
        bundle?.url(forResource: name, withExtension: nil)
            ?? bundle?.url(forResource: (name as NSString).deletingPathExtension, withExtension: "sdef")
    }
    let resources = url.appendingPathComponent("Contents/Resources")
    let inResources = ((try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? [])
        .filter { $0.hasSuffix(".sdef") }.sorted().map { resources.appendingPathComponent($0) }
    for file in [named].compactMap({ $0 }) + inResources {
        if let document = try? XMLDocument(contentsOf: file, options: [.nodeLoadExternalEntitiesNever]),
           let found = parseDictionary(document) {
            return found
        }
    }
    guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { !$0.isTerminated }) else {
        if bundleHasDictionary(url) { scriptingNote = "its dictionary is read from the app itself, so only while it runs" }
        return nil
    }
    let sdef = Process()
    sdef.executableURL = URL(fileURLWithPath: "/usr/bin/sdef")
    sdef.arguments = [url.path]
    let output = Pipe()
    sdef.standardOutput = output
    sdef.standardError = FileHandle.nullDevice
    guard (try? sdef.run()) != nil else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    sdef.waitUntilExit()
    guard sdef.terminationStatus == 0, let document = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]) else { return nil }
    return parseDictionary(document)
}

/// The commands, properties and enumerators of a dictionary's XML; `nil`
/// with neither commands nor properties.
func parseDictionary(_ document: XMLDocument) -> Scripting? {
    var scripting = Scripting()
    func attributes(_ xpath: String) -> [(code: String, name: String)] {
        ((try? document.nodes(forXPath: xpath)) ?? []).compactMap { node in
            guard let element = node as? XMLElement, let code = element.attribute(forName: "code")?.stringValue else { return nil }
            return (code, element.attribute(forName: "name")?.stringValue ?? "")
        }
    }
    for (code, name) in attributes("//command") { scripting.commands[code] = name }
    for (code, name) in attributes("//class[@name='application']/property | //class-extension[@extends='application']/property") {
        scripting.properties[code] = name
    }
    scripting.enumerators = Set(attributes("//enumerator").map(\.code))
    // A command whose direct parameter, not optional, is a document.
    for node in (try? document.nodes(forXPath: "//command[direct-parameter]")) ?? [] {
        guard let command = node as? XMLElement, let code = command.attribute(forName: "code")?.stringValue,
              let parameter = command.elements(forName: "direct-parameter").first,
              parameter.attribute(forName: "optional")?.stringValue != "yes" else { continue }
        let types = [parameter.attribute(forName: "type")?.stringValue]
            + parameter.elements(forName: "type").map { $0.attribute(forName: "type")?.stringValue }
        if types.contains("document") { scripting.documentCommands.insert(code) }
    }
    // An .sdef read as it is may only extend `document` (QuickTime Player's):
    // the class comes from Cocoa's standard suite, which it includes, as "docu".
    scripting.documentClass = attributes("//class[@name='document']").first?.code
        ?? (((try? document.nodes(forXPath: "//class-extension[@extends='document']")) ?? []).isEmpty ? nil : "docu")
    scripting.documentPlaying = attributes("//class[@name='document']/property[@name='playing']"
        + " | //class-extension[@extends='document']/property[@name='playing']").first?.code
    return scripting.commands.isEmpty && scripting.properties.isEmpty ? nil : scripting
}

say()
say("Scripting dictionary")
/// Whether the bundle carries a dictionary: an .sdef (named by its
/// Info.plist, or in its resources) or the older .scriptSuite files (VLC's).
/// Without one, `sdef` has nothing to read but the running app's.
func bundleHasDictionary(_ url: URL) -> Bool {
    if Bundle(url: url)?.object(forInfoDictionaryKey: "OSAScriptingDefinition") != nil { return true }
    let resources = (try? FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent("Contents/Resources").path)) ?? []
    return resources.contains { $0.hasSuffix(".sdef") || $0.hasSuffix(".scriptSuite") }
}
/// A press by one way reads the dictionary when the bundle has one: for the
/// script way, and its scripted state is the quickest sure sign of whether
/// the app plays, for every way (what it reports to Now Playing first opens
/// macOS's log, about 0.6 s).
let scripting = !pressingOneWay || bundleHasDictionary(appURL) ? readScripting(appURL) : nil
if let scripting {
    let playLike = scripting.commands.filter { ["play", "pause", "playpause", "stop"].contains($0.value.lowercased()) }
    say("  commands: " + (playLike.isEmpty ? "no play or pause" : playLike.sorted { $0.key < $1.key }.map { "\($0.value) (\($0.key))" }.joined(separator: ", ")))
    say("  player state (pPlS): \(scripting.hasPlayerState ? "yes" : "no")"
        + (scripting.hasPlayerState ? ", values stopped/playing/paused: \(scripting.hasStateValues ? "yes" : "no")" : ""))
    say("  sound volume (pVol): \(scripting.hasVolume ? "yes, so it can fade" : "no, so no fades")")
    if scripting.playsDocuments {
        say("  its documents: pause and play act on one (\"pause document 1\"), and each says whether it's playing:"
            + " it plays while one does, a pause pauses those playing, a play plays the front one (or those a test paused)")
    }
    if let suite = scripting.suite { say("  pause and play share suite '\(suite)'") }
} else if let scriptingNote {
    say("  not read: \(scriptingNote)")
} else {
    say("  none: it can't be scripted")
}

// MARK: - Playback menu (Accessibility, as AutoHush's AccessibilityPlaybackMenu)

// AutoHushKit's `value(_:)` and `children` read attributes, as AutoHush's players do.
extension AXUIElement {
    var actions: [String] {
        var names: CFArray?
        return AXUIElementCopyActionNames(self, &names) == .success ? names as? [String] ?? [] : []
    }
    var title: String { value(kAXTitleAttribute) as? String ?? "" }
    func text(_ attribute: String) -> String { value(attribute) as? String ?? "" }
    var frame: CGRect? {
        guard let position = value(kAXPositionAttribute), let size = value(kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
}

/// The windows last found on other desktops: the search takes about 70 ms
/// (up to 1 s), and pages are read every quarter second, so they're kept
/// for 10 s while each still answers as a window.
var otherDesktopWindows: (pid: pid_t, windows: [AXUIElement], found: Date)?

/// The app's windows on this desktop, else on any other, as AutoHush finds
/// them (`AccessibilityWindows`: about 70 ms, 1 s at most); `onThisDesktop`
/// false: not on screen, so nothing there can be hit-tested.
func appWindows(of pid: pid_t) -> (windows: [AXUIElement], onThisDesktop: Bool) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    let shown = app.elements(kAXWindowsAttribute)
    guard shown.isEmpty, AccessibilityWindows.isAvailable else { return (shown, true) }
    if let kept = otherDesktopWindows, kept.pid == pid, Date().timeIntervalSince(kept.found) < 10,
       !kept.windows.isEmpty, kept.windows.allSatisfy({ $0.text(kAXRoleAttribute) == kAXWindowRole }) {
        return (kept.windows, false)
    }
    let found = AccessibilityWindows.windows(ofProcess: pid) ?? []
    otherDesktopWindows = (pid, found, Date())
    return (found, false)
}

struct FoundMenu {
    let title: String
    let toggle: AXUIElement
    /// Found as AutoHush finds it (⌘← and ⌘→); otherwise only by its arrows
    /// with other modifiers, which AutoHush doesn't look for.
    let asAutoHushFindsIt: Bool
    /// Its Previous and Next shortcuts, e.g. "⌘← ⌘→" or "⇧← ⇧→".
    let arrows: String
    var toggleTitle: String { toggle.title }
    var toggleEnabled: Bool { toggle.value(kAXEnabledAttribute) as? Bool ?? false }
}

/// The menu whose items include ⌘← and ⌘→ (Previous and Next), with Play or
/// Pause first: how AutoHush finds it whatever the app's language. Else one
/// whose first item is on Space and that has ← and → under other modifiers
/// (Deezer's Play menu: Space, ⇧← and ⇧→), which AutoHush wouldn't find as
/// it is. Looked up afresh each time, as some apps rebuild their menus on
/// every change.
func playbackMenu(pid: pid_t) -> FoundMenu? {
    let app = AXUIElementCreateApplication(pid)
    // As AutoHush waits for a menu (`AccessibilityPlaybackMenu.timeout`).
    AXUIElementSetMessagingTimeout(app, AccessibilityPlaybackMenu.timeout)
    guard let bar = app.value(kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
    let menuBar = bar as! AXUIElement
    var other: FoundMenu?
    for barItem in menuBar.children {
        guard let menu = barItem.children.first, let first = menu.children.first else { continue }
        // Each arrow key's modifiers, every item's (AXMenuItemCmdModifiers: 0 is ⌘ alone):
        // TIDAL has ⌘← for Previous and ⇧⌘← for Seek back.
        var arrows: [Int: [Int]] = [:]
        for item in menu.children {
            if let key = item.value(kAXMenuItemCmdVirtualKeyAttribute) as? Int, key == 123 || key == 124 {
                arrows[key, default: []].append(item.value(kAXMenuItemCmdModifiersAttribute) as? Int ?? 0)
            }
        }
        guard let left = arrows[123], let right = arrows[124] else { continue }
        if left.contains(0), right.contains(0) {
            return FoundMenu(title: barItem.title, toggle: first, asAutoHushFindsIt: true, arrows: "⌘← ⌘→")
        }
        if other == nil, first.value(kAXMenuItemCmdVirtualKeyAttribute) as? Int == 49 {
            other = FoundMenu(title: barItem.title, toggle: first, asAutoHushFindsIt: false,
                                 arrows: "\(modifierSymbols(left[0]))← \(modifierSymbols(right[0]))→")
        }
    }
    return other
}

/// Its Play/Pause item as it reads now: for a menu found as AutoHush finds
/// it, through AutoHush's own `AccessibilityPlaybackMenu`; else this tool's.
func menuToggle(pid: pid_t) -> MenuToggle? {
    if menu?.asAutoHushFindsIt == true, let toggle = AccessibilityPlaybackMenu().toggle(pid: pid) { return toggle }
    return playbackMenu(pid: pid).map { MenuToggle(title: $0.toggleTitle, isEnabled: $0.toggleEnabled) }
}

/// Presses its Play/Pause item, as AutoHush presses it when it finds the
/// menu its way (`AccessibilityPlaybackMenu.pressToggle`).
func pressMenuToggle(pid: pid_t) -> Bool {
    if menu?.asAutoHushFindsIt == true, AccessibilityPlaybackMenu().pressToggle(pid: pid) { return true }
    guard let item = playbackMenu(pid: pid)?.toggle else { return false }
    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
}

/// What its menu's Play/Pause item says of the state, as AutoHush's
/// MenuPlayer reads it: disabled, it's stopped (nothing to play); else by
/// the app's own words (`MenuPlayer.state(of:words:)`), else by this tool's
/// list ("Pause" while it plays). Nil when the item says neither.
func menuState(_ toggle: MenuToggle) -> String? {
    guard toggle.isEnabled else { return "stopped" }
    if let ownWords {
        let state = MenuPlayer.state(of: toggle, words: ownWords)
        if state != .unknown { return state.rawValue }
    }
    let title = toggle.title.lowercased()
    return pauseWords.contains(title) ? "playing" : playWords.contains(title) ? "paused" : nil
}

/// The symbols of AXMenuItemCmdModifiers: ⇧ 1, ⌥ 2, ⌃ 4, and 8 for no ⌘.
func modifierSymbols(_ modifiers: Int) -> String {
    (modifiers & 4 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "") + (modifiers & 1 != 0 ? "⇧" : "")
        + (modifiers & 8 != 0 ? "" : "⌘")
}

// MARK: - The app's own words for Play and Pause

/// The app's own words for Play and Pause, in every language it has, as
/// AutoHush's menu players read theirs (TidalWords, PodcastsWords), found the
/// same way in any app: the texts of a translation table whose English is
/// "Play" or "Pause" (`.loctable`, as Podcasts'; `*.lproj/*.strings`), and,
/// in an Electron app's `app.asar`, every text of the keys whose text is
/// "Play" or "Pause" (as TIDAL's "t-play"). Read once per copy and version
/// (kept in ~/Library/Caches/PlayerCheck/words.json); nil when none show.
func appWords(of url: URL) -> (words: PlayPauseWords, source: String)? {
    struct Kept: Codable { var play: [String]; var pause: [String]; var source: String }
    let cacheFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/PlayerCheck/words.json")
    let key = "\(url.path)#\(Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")"
    var cache = (try? JSONDecoder().decode([String: Kept?].self, from: Data(contentsOf: cacheFile))) ?? [:]
    if let kept = cache[key] {
        return kept.map { (PlayPauseWords(play: Set($0.play), pause: Set($0.pause)), $0.source) }
    }
    let resources = url.appendingPathComponent("Contents/Resources")
    let files = FileManager.default
    var play: Set<String> = [], pause: Set<String> = [], sources: [String] = []
    func take(_ tables: [[String: String]], english: [String: String], from source: String) {
        let playKeys = english.filter { $0.value == "Play" }.keys, pauseKeys = english.filter { $0.value == "Pause" }.keys
        guard !playKeys.isEmpty || !pauseKeys.isEmpty else { return }
        for table in tables {
            play.formUnion(playKeys.compactMap { table[$0] })
            pause.formUnion(pauseKeys.compactMap { table[$0] })
        }
        sources.append(source)
    }
    let names = (try? files.contentsOfDirectory(atPath: resources.path)) ?? []
    // Every language in one property list (Podcasts' Localizable.loctable).
    for name in names where name.hasSuffix(".loctable") {
        guard let data = try? Data(contentsOf: resources.appendingPathComponent(name), options: .alwaysMapped),
              let languages = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { continue }
        let tables = languages.compactMapValues { ($0 as? [String: Any])?.compactMapValues { $0 as? String } }
        if let english = tables["en"] ?? tables["English"] ?? tables["Base"] { take(Array(tables.values), english: english, from: name) }
    }
    // One folder per language (Localizable.strings and the like).
    let languages = names.filter { $0.hasSuffix(".lproj") }
    if let englishFolder = ["en.lproj", "English.lproj", "Base.lproj"].first(where: languages.contains) {
        let stringsFiles = ((try? files.contentsOfDirectory(atPath: resources.appendingPathComponent(englishFolder).path)) ?? [])
            .filter { $0.hasSuffix(".strings") }
        for file in stringsFiles {
            func table(_ folder: String) -> [String: String]? {
                NSDictionary(contentsOf: resources.appendingPathComponent("\(folder)/\(file)")) as? [String: String]
            }
            guard let english = table(englishFolder) else { continue }
            take(languages.compactMap(table), english: english, from: "\(englishFolder)/\(file)")
        }
    }
    // An Electron app's translations, inside app.asar as JSON.
    if let asar = try? Data(contentsOf: resources.appendingPathComponent("app.asar"), options: .alwaysMapped) {
        /// The JSON string starting at `index` (a quote), decoded, and the index after it.
        func string(at index: Data.Index) -> (String, Data.Index)? {
            guard index < asar.endIndex, asar[index] == UInt8(ascii: "\"") else { return nil }
            var end = index + 1
            while end < asar.endIndex, asar[end] != UInt8(ascii: "\"") { end += asar[end] == UInt8(ascii: "\\") ? 2 : 1 }
            guard end < asar.endIndex, end - index < 200, let text = try? JSONDecoder().decode(String.self, from: asar[index...end]) else { return nil }
            return (text, end + 1)
        }
        /// The keys whose text is `word`: `"<key>": "<word>"`.
        func keys(of word: String) -> Set<String> {
            var found: Set<String> = [], start = asar.startIndex
            let marker = Data("\"\(word)\"".utf8)
            while found.count < 8, let range = asar.range(of: marker, in: start..<asar.endIndex) {
                start = range.upperBound
                var colon = range.lowerBound - 1
                while colon > asar.startIndex, asar[colon] == UInt8(ascii: " ") { colon -= 1 }
                guard asar[colon] == UInt8(ascii: ":") else { continue }
                var close = colon - 1
                while close > asar.startIndex, asar[close] == UInt8(ascii: " ") { close -= 1 }
                guard asar[close] == UInt8(ascii: "\"") else { continue }
                var open = close - 1
                while open > asar.startIndex, asar[open] != UInt8(ascii: "\""), close - open < 80 { open -= 1 }
                if let (key, _) = string(at: open), !key.isEmpty { found.insert(key) }
            }
            return found
        }
        /// Every text of `key`: `"<key>": "…"`.
        func texts(of key: String) -> Set<String> {
            var found: Set<String> = [], start = asar.startIndex
            let marker = Data("\"\(key)\":".utf8)
            while let range = asar.range(of: marker, in: start..<asar.endIndex) {
                start = range.upperBound
                var index = range.upperBound
                while index < asar.endIndex, asar[index] == UInt8(ascii: " ") { index += 1 }
                if let (text, _) = string(at: index), !text.isEmpty { found.insert(text) }
            }
            return found
        }
        let playTexts = keys(of: "Play").reduce(into: Set<String>()) { $0.formUnion(texts(of: $1)) }
        let pauseTexts = keys(of: "Pause").reduce(into: Set<String>()) { $0.formUnion(texts(of: $1)) }
        if !playTexts.isEmpty || !pauseTexts.isEmpty {
            play.formUnion(playTexts)
            pause.formUnion(pauseTexts)
            sources.append("app.asar")
        }
    }
    let found = play.isEmpty && pause.isEmpty ? nil
        : Kept(play: play.sorted(), pause: pause.sorted(), source: sources.joined(separator: ", "))
    cache[key] = .some(found)
    try? files.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? JSONEncoder().encode(cache).write(to: cacheFile)
    return found.map { (PlayPauseWords(play: Set($0.play), pause: Set($0.pause)), $0.source) }
}

/// The app's own words, for its menu's state and its page's buttons, merged
/// with this tool's list (`playWords`, `pauseWords`). A press reads them only
/// for the menu or the page (kept, they cost a file read).
let ownAppWords = !pressingOneWay || via == "menu" || via == "page" ? appWords(of: appURL) : nil
let ownWords = ownAppWords?.words

say()
say("Playback menu")
var menu: FoundMenu?
/// Whether something surer than its menu's or page's word shows whether it
/// plays: its scripted state, or what it reports to Now Playing.
let hasSurerSign = scripting?.hasState == true || nowPlayingReason(of: appURL, bundleID: bundleID) != nil
/// A press by one way reads the menu and the page for their own way (the
/// panel needs the page's player bar, which names the song), or when nothing
/// surer shows whether the app plays.
func pressNeeds(_ ways: Set<String>) -> Bool { !pressingOneWay || ways.contains(via!) || !hasSurerSign }
if !pressNeeds(["menu"]) {
    say("  not read: --via \(via!) doesn't need it")
} else if running == nil {
    say("  not checked: the app isn't running")
} else if !AXIsProcessTrusted() {
    say("  not checked: this tool (or the app running it) needs the Accessibility permission")
} else if let found = playbackMenu(pid: running!.processIdentifier) {
    menu = found
    say("  '\(found.title)': first item '\(found.toggleTitle)', "
        + (found.toggleEnabled ? "enabled" : "disabled (nothing to play now, or nobody signed in)"))
    if !found.asAutoHushFindsIt {
        say("  its Previous and Next are \(found.arrows), not ⌘← ⌘→: AutoHush wouldn't find this menu as it is")
    }
    say("  " + (ownAppWords.map { "its own words for Play and Pause, as AutoHush's menu players read them: \($0.words.play.count) and"
                                 + " \($0.words.pause.count), from \($0.source)" }
                ?? "its own words for Play and Pause weren't found in its bundle: its item is read with this tool's list"))
} else {
    say("  none: no menu with ⌘← and ⌘→, nor one with its first item on Space and other arrows")
}

// MARK: - Sound

/// The process macOS holds responsible for `pid` (the app behind a helper),
/// as AutoHush asks it (`ProcessResponsibility`); itself when unknown.
func responsible(_ pid: pid_t) -> pid_t { ProcessResponsibility.responsiblePID(for: pid) ?? pid }

/// An app's name, else its executable's.
func processName(_ pid: pid_t) -> String {
    if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return "pid \(pid)" }
    return URL(fileURLWithPath: String(cString: path)).lastPathComponent
}

/// The processes with sound output running that the app owns (its own, or
/// helpers such as a web app's WebKit process), found as AutoHush finds a
/// player's (`OwnedAudioProcesses`), as "name (bundle ID, pid)".
func soundProcesses(of pid: pid_t) -> [String] {
    OwnedAudioProcesses.objects(ownedBy: pid).compactMap { object in
        guard CoreAudioProperty.value(kAudioProcessPropertyIsRunningOutput, of: object, initial: UInt32(0)) == 1,
              let processPID = CoreAudioProperty.value(kAudioProcessPropertyPID, of: object, initial: pid_t(0)) else { return nil }
        let id = CoreAudioProperty.string(kAudioProcessPropertyBundleID, of: object) ?? ""
        return "\(processName(processPID)) (\(id.isEmpty ? "no bundle ID" : id), pid \(processPID))"
    }.sorted()
}

/// Whether its sound is measured, as AutoHush judges sound by default: by
/// its level, through process taps, which need System Audio Recording (and
/// show macOS's recording indicator while they listen). A check asks for it
/// when it's undecided; a press only uses it when it's allowed.
var levelsAllowed = false
func setUpLevels(asking: Bool) {
    let permission = TCCAudioCapturePermission()
    var status = permission.status()
    if status == .notDetermined, asking {
        say("  System Audio Recording: asked (to measure its sound as AutoHush does)")
        let answer = OSAllocatedUnfairLock<Bool?>(initialState: nil)
        permission.request { granted in answer.withLock { $0 = granted } }
        let deadline = Date().addingTimeInterval(120)
        while answer.withLock({ $0 }) == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        status = answer.withLock { $0 } == true ? .granted : permission.status()
    }
    levelsAllowed = status == .granted
    guard asking else { return }
    switch status {
    case .granted?:
        say("  its level: measured as AutoHush measures it (process taps; macOS shows its recording indicator meanwhile)")
    case .denied?, .notDetermined?:
        say("  its level: not measured: System Audio Recording isn't allowed (System Settings → Privacy & Security →"
            + " Screen & System Audio Recording); judged by what it tells macOS and its open output instead")
    case nil:
        say("  its level: not measured: whether System Audio Recording is allowed can't be asked")
    }
}

/// Whether it can be heard now, by its level (half a second of listening,
/// AutoHush's threshold: `ProcessTapLevelProbe`); nil when it isn't measured.
func audible(_ pid: pid_t) -> Bool? {
    levelsAllowed ? ProcessTapLevelProbe().isAudible(appPID: pid) : nil
}

/// Its own keep-awake assertions now (its processes' and helpers'), as
/// AutoHush's AntiDot mode reads them (`IOKitPowerAssertionReader`): media
/// apps hold one while they play and let it go when they pause, though their
/// output stays open.
func assertions(of pid: pid_t) -> Set<PowerAssertion> {
    IOKitPowerAssertionReader().assertionsByProcess()
        .filter { ProcessResponsibility.isOwned($0.key, by: pid) }
        .reduce(into: Set()) { $0.formUnion($1.value) }
}

/// Whether it plays as its assertions tell it, AntiDot mode's rule: holding
/// its own "keep the Mac awake" one, it plays; seen holding one while its
/// sound was on (in this run), but not now, it's paused; nil while it never did.
var heldWhileSounding = false
func awake(_ pid: pid_t, sounding: Bool) -> Bool? {
    let held = assertions(of: pid).contains { $0.kind == .system }
    if held, sounding { heldWhileSounding = true }
    return held ? true : heldWhileSounding ? false : nil
}

say()
say("Sound and Now Playing")
// Only shown, so not read for --play or --pause (it asks a second copy of
// this tool who's Now Playing: about 0.3 s).
if action != nil {
    say("  not read: only shown in a check")
    setUpLevels(asking: false)
} else if let running {
    let sound = soundProcesses(of: running.processIdentifier)
    say("  sound output running now: " + (sound.isEmpty ? "none (it isn't playing)" : sound.joined(separator: "; ")))
    setUpLevels(asking: true)
    if levelsAllowed { say("  heard now: " + (audible(running.processIdentifier) == true ? "yes" : "no")) }
    let held = assertions(of: running.processIdentifier)
    say("  keeps the Mac awake: " + (held.isEmpty ? "no assertion now (media apps hold one while they play, as AntiDot mode reads it)"
        : held.sorted { $0.name < $1.name }.map { "'\($0.name)'" + ($0.kind == .display ? " (display only)" : "") }.joined(separator: ", ")))
    _ = awake(running.processIdentifier, sounding: !sound.isEmpty)
    let holder = nowPlayingPID()
    let holds = holder > 0 && (holder == running.processIdentifier || responsible(holder) == running.processIdentifier)
    let other = holder == 0 ? "no app" : NSRunningApplication(processIdentifier: responsible(holder))?.localizedName ?? "pid \(holder)"
    say("  Now Playing: " + (holder < 0 ? "MediaRemote didn't answer"
        : holds ? "this app (until another app reports playing)"
        : holder == 0 ? "no app" : "another app (\(other))"))
} else {
    say("  not checked: the app isn't running")
}

// MARK: - Page buttons (a web page in its windows, or a Flutter app's interface)

/// The switches for assistive tools: attributes set on an app to have it
/// show its interface to Accessibility. Electron's is documented
/// (electronjs.org, Accessibility); VoiceOver's is the one VoiceOver sets.
/// Computed, so `--now-playing-reasons`, which runs before this line, can
/// name them.
var manualAccessibility: String { "AXManualAccessibility" }
var enhancedUserInterface: String { "AXEnhancedUserInterface" }
func switchName(_ attribute: String) -> String {
    attribute == manualAccessibility ? "Electron's switch" : "VoiceOver's switch"
}

/// An interface the app keeps out of Accessibility until an assistive tool
/// asks for it, by the framework in its bundle, with the switches that ask,
/// in the order they're tried:
/// - Electron: its own, `AXManualAccessibility`;
/// - Chromium Embedded Framework (CEF; Spotify): none of its own, as each
///   app decides: Electron's, else VoiceOver's `AXEnhancedUserInterface`,
///   which CEF's sample app listens to (Spotify takes only that one);
/// - Flutter (Spotube): VoiceOver's only (Flutter's engine listens for it).
/// Electron's and CEF's interface is a web page, as a Safari web app's;
/// Flutter's is the window's own elements. Any other app's web page (as in
/// a Tauri app, Safari's WebKit) shows as it is.
enum HiddenInterface {
    case electron(version: String), cef, flutter
    var name: String {
        switch self {
        case .electron(let version): "Electron \(version)"
        case .cef: "Chromium (CEF)"
        case .flutter: "Flutter"
        }
    }
    var switches: [String] {
        switch self {
        case .electron: [manualAccessibility]
        case .cef: [manualAccessibility, enhancedUserInterface]
        case .flutter: [enhancedUserInterface]
        }
    }
    /// The app's, by the frameworks in its bundle.
    static func of(_ appURL: URL) -> HiddenInterface? {
        let frameworks = appURL.appendingPathComponent("Contents/Frameworks")
        func framework(_ name: String) -> URL? {
            let url = frameworks.appendingPathComponent("\(name).framework")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let electron = framework("Electron Framework") {
            return .electron(version: Bundle(url: electron)?.infoDictionary?["CFBundleVersion"] as? String ?? "?")
        }
        if framework("Chromium Embedded Framework") != nil { return .cef }
        if framework("FlutterMacOS") != nil { return .flutter }
        return nil
    }
}
let hiddenInterface = HiddenInterface.of(appURL)
var isFlutter: Bool { if case .flutter? = hiddenInterface { true } else { false } }

/// Play and Pause as players' pages name their buttons (any case), in
/// English, Spanish, Catalan and a few more, and the app's own words: what
/// this tool looks for and presses until it learns the button, as AutoHush
/// does, by its words changing (`learnPageButton`), in any language.
/// The app's own words join them only for an app whose page comes from its
/// own bundle (Electron, CEF, Flutter): a native app's words name its menu
/// items, and one of them ("Main", Indonesian for Play) would make a page's
/// "Main menu" a Play button. A menu's item is told by them exactly (`menuState`).
let pageOwnWords = hiddenInterface == nil ? nil : ownWords
let playWords = Set(["play", "reproducir", "reprodueix", "reproduir", "lecture", "lire", "wiedergabe",
                     "abspielen", "riproduci", "reproduzir"])
    .union(pageOwnWords?.play.map { $0.lowercased() } ?? [])
let pauseWords = Set(["pause", "pausa", "pausar", "posa en pausa", "mettre en pause", "pausieren"])
    .union(pageOwnWords?.pause.map { $0.lowercased() } ?? [])
let playPauseWords = playWords.union(pauseWords)

/// Whether a button's name is one of `words`, alone or first ("Pause
/// current", SoundCloud's player bar; "Play Chill House", a tile, also
/// matches: the bar wins by its slider).
func named(_ label: String, _ words: Set<String>) -> Bool {
    let label = label.lowercased()
    return words.contains { label == $0 || label.hasPrefix($0 + " ") }
}

/// What an element is called: as AutoHush names a web app's button, its
/// description, else its title; else its value (a Flutter app's pressable
/// text keeps its words there).
func label(of element: AXUIElement) -> String {
    [element.text(kAXDescriptionAttribute), element.title, element.text(kAXValueAttribute)].first { !$0.isEmpty } ?? ""
}

/// A button of the app's page (a pressable item of a Flutter app's
/// interface), named by `label(of:)`.
struct FoundButton {
    let element: AXUIElement
    let label: String
    /// Points from its middle to its window's bottom; nil without a frame.
    let fromBottom: Double?
    /// Inside its window. One scrolled out of an Electron window is squeezed
    /// to no height at the window's edge (Deezer's song tiles), so it isn't.
    let inSight: Bool
    /// In a window on screen (on this desktop, not minimised, its app not
    /// hidden), so it can be hit-tested.
    let onScreen: Bool
}

/// Roles never walked into looking for a page: a native app's long lists
/// (Music's songs) hold none.
let listRoles: Set<String> = [kAXTableRole, kAXOutlineRole, kAXBrowserRole, kAXListRole, "AXGrid", kAXTextAreaRole]

/// The web pages (AXWebArea) in a window, as AutoHush's web app reader
/// finds them (up to 16 levels down), nearest first, reading at most 2,000
/// of its elements, so a native app's window isn't read whole.
func webAreas(in window: AXUIElement) -> [AXUIElement] {
    var found: [AXUIElement] = [], queue: [(AXUIElement, Int)] = [(window, 0)], next = 0
    while next < queue.count, next < 2000 {
        let (element, depth) = queue[next]
        next += 1
        let role = element.text(kAXRoleAttribute)
        if role == "AXWebArea" {
            found.append(element)
        } else if depth < 16, !listRoles.contains(role) {
            queue += element.children.map { ($0, depth + 1) }
        }
    }
    return found
}

/// A Flutter window's items that can be pressed (its buttons, and the texts
/// and images it marks pressable), reading at most 3,000 of its elements;
/// not the window's own close, minimise and full-screen buttons.
func pressableItems(in window: AXUIElement) -> [AXUIElement] {
    var found: [AXUIElement] = [], queue: [(AXUIElement, Int)] = [(window, 0)], next = 0
    while next < queue.count, next < 3000 {
        let (element, depth) = queue[next]
        next += 1
        if depth == 1, element.text(kAXRoleAttribute) == kAXButtonRole { continue }
        if depth > 0, element.actions.contains(kAXPressAction) { found.append(element) }
        if depth < 40 { queue += element.children.map { ($0, depth + 1) } }
    }
    return found
}

/// Whether one of the app's windows holds a web page.
func hasWebPage(pid: pid_t) -> Bool {
    appWindows(of: pid).windows.contains { !webAreas(in: $0).isEmpty }
}

/// The buttons of the pages in the app's windows, found as AutoHush's web
/// app reader finds them (each window's AXWebArea on this desktop, else on
/// another, then AXUIElementsForSearchPredicate), or a Flutter app's
/// pressable items; nil when it has no window.
func pageButtons(pid: pid_t) -> [FoundButton]? {
    let (windows, onThisDesktop) = appWindows(of: pid)
    guard !windows.isEmpty else { return nil }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    let hidden = app.value(kAXHiddenAttribute) as? Bool == true
    let search: [String: Any] = ["AXSearchKey": "AXButtonSearchKey", "AXResultsLimit": 2000, "AXDirection": "AXDirectionNext",
                                 "AXVisibleOnly": false, "AXImmediateDescendantsOnly": false]
    return windows.flatMap { window -> [FoundButton] in
        AXUIElementSetMessagingTimeout(window, 1)
        guard let windowFrame = window.frame else { return [] }
        let onScreen = onThisDesktop && !hidden && window.value(kAXMinimizedAttribute) as? Bool != true
        let elements = isFlutter ? pressableItems(in: window) : webAreas(in: window).flatMap { area -> [AXUIElement] in
            var result: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(area, "AXUIElementsForSearchPredicate" as CFString,
                                                             search as CFDictionary, &result) == .success else { return [] }
            return result as? [AXUIElement] ?? []
        }
        return elements.map { element in
            AXUIElementSetMessagingTimeout(element, 0.5)
            let frame = element.frame
            return FoundButton(element: element, label: label(of: element),
                              fromBottom: frame.map { Double(windowFrame.maxY - $0.midY) },
                              inSight: frame.map { $0.width > 0 && $0.height > 0
                                  && (windowFrame.minY...windowFrame.maxY).contains($0.midY) } ?? false,
                              onScreen: onScreen)
        }
    }
}

/// The player's bar around the button: its nearest parent (three levels up
/// within the page, each read six deep, 500 elements at most) holding a
/// slider or a progress bar, as a player's bar has. Having one is what
/// AutoHush's learning weighs (`ButtonStanding.isWithPlayerControls`).
func playerBar(of element: AXUIElement) -> AXUIElement? {
    var reads = 500
    func holdsSlider(_ element: AXUIElement, depth: Int) -> Bool {
        guard reads > 0 else { return false }
        reads -= 1
        let role = element.text(kAXRoleAttribute)
        if role == kAXSliderRole || role == kAXProgressIndicatorRole { return true }
        return depth < 6 && element.children.contains { holdsSlider($0, depth: depth + 1) }
    }
    var node = element
    for _ in 0..<3 {
        guard let parent = node.value(kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
        node = parent as! AXUIElement
        if node.text(kAXRoleAttribute) == "AXWebArea" { return nil }
        if holdsSlider(node, depth: 0) { return node }
    }
    return nil
}

/// Whether nothing on its page sits over the button's middle: macOS's hit
/// test there (within the app) finds the button or something inside it.
/// Song tiles scrolled under a player bar (Deezer's, SoundCloud's) are in
/// the window, lower than the bar's own button, but covered. One hit test:
/// `playerButton` asks Chromium's approximate misses again.
func isUncovered(_ button: FoundButton, pid: pid_t) -> Bool {
    // Off screen (another desktop, hidden, minimised): whatever is there would answer.
    guard button.onScreen else { return true }
    guard let frame = button.element.frame else { return false }
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(pid), Float(frame.midX), Float(frame.midY), &hit) == .success,
          var node = hit else { return true } // can't tell: keep it
    for _ in 0..<8 {
        if CFEqual(node, button.element) { return true }
        guard let parent = node.value(kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
        node = parent as! AXUIElement
    }
    return false
}

/// The player's button named one of `words` (any case, alone or first),
/// ranked as AutoHush's learning ranks them: of those in sight and not
/// covered, the lowest with a player's slider or progress bar around it,
/// else the lowest (players keep their controls at the bottom).
func playerButton(pid: pid_t, named words: Set<String>) -> (button: FoundButton, withControls: Bool)? {
    let candidates = (pageButtons(pid: pid) ?? [])
        .filter { $0.inSight && named($0.label, words) }
        .sorted { ($0.fromBottom ?? .infinity) < ($1.fromBottom ?? .infinity) }
    var bars: [Int: Bool] = [:]
    func hasBar(_ index: Int) -> Bool {
        if let known = bars[index] { return known }
        let found = playerBar(of: candidates[index].element) != nil
        bars[index] = found
        return found
    }
    // Each is hit-tested once. Chromium answers a hit test from its last one
    // at first, then precisely a moment later (Spotify's bar button behind
    // other windows: a group elsewhere, then the button), so the misses are
    // asked again together, once, 0.2 s later: only when one of them could
    // change which button wins, being lower than the first uncovered one with
    // a player bar (Deezer's tiles under its bar can't).
    var open = candidates.map { isUncovered($0, pid: pid) }
    let firstBar = candidates.indices.first { open[$0] && hasBar($0) }
    if open.prefix(firstBar ?? candidates.count).contains(false) {
        Thread.sleep(forTimeInterval: 0.2)
        for index in candidates.indices where !open[index] { open[index] = isUncovered(candidates[index], pid: pid) }
    }
    var lowest: FoundButton?
    for index in candidates.indices where open[index] {
        if hasBar(index) { return (candidates[index], true) }
        if lowest == nil { lowest = candidates[index] }
    }
    return lowest.map { ($0, false) }
}

/// Waits up to `seconds` until the page's count of buttons holds for 0.75 s:
/// the count, and how long it took to settle.
func waitForPage(_ pid: pid_t, seconds: Double) -> (count: Int, after: TimeInterval) {
    let start = Date()
    var count = 0, changed = start
    while Date().timeIntervalSince(start) < seconds, count == 0 || Date().timeIntervalSince(changed) < 0.75 {
        Thread.sleep(forTimeInterval: 0.25)
        let now = pageButtons(pid: pid)?.count ?? 0
        if now != count { count = now; changed = Date() }
    }
    return (count, changed.timeIntervalSince(start))
}

/// Brings an app forward through Launch Services, as `open` does (an app
/// in the background may not activate another itself).
func bringForward(_ url: URL) {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = [url.path]
    try? open.run()
    open.waitUntilExit()
}

/// Set when the app had to be brought forward for its page to show.
var broughtForward = false

/// The page's Play/Pause in its player bar, found last, and the last full
/// search's answer while there's no bar (see `pageToggleLabel`).
var barToggle: AXUIElement?
var lastSearch = Date.distantPast, lastSearchLabel: String?

/// What the page showed: how many buttons (0: none), and the player's
/// Play/Pause, with or without a player's slider around it (without, it's
/// likely a song's own button: nothing loaded, or nobody signed in).
struct PageCheck {
    let buttons: Int
    let toggle: FoundButton?
    var withControls = false
}

say()
say("Page buttons")
var page: PageCheck?
/// Why the page wasn't checked, for the summary.
var pageNotChecked: String?
/// The switch that showed the page; nil when it showed without one.
var pageSwitch: String?

/// A stop (Ctrl-C, or the Player Check app's Stop) arrives on another thread.
/// Between a trial's pause and its play it only asks: the trial plays the app
/// again, then the tool stops. Otherwise the tool stops at once, after putting
/// back what it changed: the switches it turned on, and the app that was in
/// front when it brought the checked one forward.
final class StopState: @unchecked Sendable {
    private let lock = NSLock()
    private var inTrial = false, requested = false
    private var front: URL?
    private var switches: [String] = []
    /// The switches this tool turned on: turned back off when it ends.
    var switchesOn: [String] {
        get { lock.withLock { switches } }
        set { lock.withLock { switches = newValue } }
    }
    func setInTrial(_ value: Bool) { lock.withLock { inTrial = value } }
    /// Records the stop; true when a trial must finish first.
    func request() -> Bool { lock.withLock { requested = true; return inTrial } }
    var isRequested: Bool { lock.withLock { requested } }
    /// The app to bring back to the front, while another was brought forward.
    var frontToRestore: URL? {
        get { lock.withLock { front } }
        set { lock.withLock { front = newValue } }
    }
    private var stream: pid_t = 0
    /// The `log stream` this tool follows Now Playing with, ended with it.
    var streamPID: pid_t {
        get { lock.withLock { stream } }
        set { lock.withLock { stream = newValue } }
    }
}
let stopState = StopState()

/// Sets a switch on the app; whether it took. An app may answer an error
/// yet take it (Spotify and Spotube answer -25208 to VoiceOver's switch, and
/// read it back as set), or read one back as off while it's on (Deezer,
/// Electron's): either sign counts.
func setSwitch(_ attribute: String, _ on: Bool, pid: pid_t) -> Bool {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    if AXUIElementSetAttributeValue(app, attribute as CFString, on ? kCFBooleanTrue : kCFBooleanFalse) == .success { return true }
    return app.value(attribute) as? Bool == on
}

/// Turns the switches this tool turned on back off: those that didn't go.
@discardableResult
func switchesBackOff() -> [String] {
    guard let pid = running?.processIdentifier else { return [] }
    let stuck = stopState.switchesOn.filter { !setSwitch($0, false, pid: pid) }
    stopState.switchesOn = []
    return stuck
}

/// Puts back what the tool changed, then ends at once: `_exit`, as `exit`
/// could wait on the main thread's locks (stdout) from the stop's thread.
func stopNow(_ code: Int32) -> Never {
    log("(stopped)")
    switchesBackOff()
    if let front = stopState.frontToRestore { bringForward(front) }
    if stopState.streamPID > 0 { kill(stopState.streamPID, SIGTERM) }
    fflush(stdout)
    _exit(code)
}

/// After a trial: the stop it held back.
func stopIfRequested() {
    guard stopState.isRequested else { return }
    say("  stopped: \(appName) was played again first")
    stopNow(143)
}

for stop in [SIGINT, SIGTERM] { signal(stop, SIG_IGN) }
let stopSources = [SIGINT, SIGTERM].map { stop in
    let source = DispatchSource.makeSignalSource(signal: stop, queue: .global())
    source.setEventHandler {
        if stopState.request() { return } // the trial plays it again, then stops
        stopNow(128 + stop)
    }
    source.resume()
    return source
}
/// Whoever ran it may go without a word: Player Check's window closed, or
/// the app quit by force or crashed. Its output then goes nowhere (and
/// SIGPIPE is ignored), so it stops as for Ctrl-C when its parent ends,
/// rather than going on with the check unwatched.
let parentPID = getppid()
let parentSource: DispatchSourceProcess? = parentPID > 1 ? {
    let source = DispatchSource.makeProcessSource(identifier: parentPID, eventMask: .exit, queue: .global())
    source.setEventHandler {
        if stopState.request() { return }
        stopNow(143)
    }
    source.resume()
    return source
}() : nil
// Gone already, before the watch began: this process went to launchd.
if parentSource != nil, getppid() != parentPID, !stopState.request() { stopNow(143) }
/// Turns a switch on; whether the app took it. One this tool turned on is
/// turned back off at the end, unless it may have been on before: VoiceOver's
/// reads back, so one already on is left alone; Electron's reads back off
/// even while it's on (Deezer), so with the page readable already (someone
/// may have it on) a check leaves it on. A press always turns it off at the
/// end (the user, 2026-10-11): it leaves the app as it found it, and a page
/// kept for later goes stale out of sight (Deezer's took no presses after
/// minutes on another desktop).
func turnOn(_ attribute: String, pid: pid_t, pageReadable: Bool) -> Bool {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    if attribute == enhancedUserInterface, app.value(attribute) as? Bool == true {
        say("  \(switchName(attribute)) (\(attribute)) is on already: VoiceOver or another tool turned it on, so it's left on")
        return true
    }
    guard setSwitch(attribute, true, pid: pid) else {
        say("  \(switchName(attribute)) (\(attribute)): not taken")
        return false
    }
    if attribute == manualAccessibility, pageReadable, action == nil {
        say("  \(switchName(attribute)) on, and left on: VoiceOver or another tool may have it on")
    } else {
        stopState.switchesOn.append(attribute)
    }
    return true
}

/// Turns `attribute` on and waits for the page: whether a page showed (in
/// `count`, after `shownAfter` s), nil when the app didn't take the switch.
/// A Chromium app builds its page only while its window can be seen
/// (Deezer's, covered: none), and once built it stays readable covered,
/// hidden or on another desktop; Spotify, on another desktop when its
/// switch went on, and Spotube, behind other windows, showed nothing until
/// the switch went on again in front. So when nothing shows, a check brings
/// the app forward a moment with the switch turned off and on again, then
/// the app that was in front. A press never does (the user, 2026-10-11: the
/// tool should be as unintrusive as possible): it says why the page can't
/// be read, and the page way isn't used.
func showPage(with attribute: String, pid: pid_t, count: inout Int, shownAfter: inout TimeInterval?) -> Bool? {
    guard turnOn(attribute, pid: pid, pageReadable: false) else { return nil }
    var waited = waitForPage(pid, seconds: 4)
    var seconds = 4
    if waited.count == 0, action == nil {
        waited = inFront(pid: pid) {
            if stopState.switchesOn.contains(attribute) {
                _ = setSwitch(attribute, false, pid: pid)
                _ = setSwitch(attribute, true, pid: pid)
            }
            return waitForPage(pid, seconds: 6)
        }
        seconds += 6
        say("  its window was out of sight: brought it forward a moment, with the switch turned on again there"
            + " (Chromium and Flutter apps may build their \(isFlutter ? "interface" : "page") only while their window can be seen)")
    }
    guard waited.count > 0 else {
        say("  \(switchName(attribute)) (\(attribute)) on, but nothing showed in \(seconds) s")
        if action != nil {
            pageOutOfView = true
        }
        if stopState.switchesOn.contains(attribute), setSwitch(attribute, false, pid: pid) {
            stopState.switchesOn.removeAll { $0 == attribute }
        }
        return false
    }
    count = waited.count
    shownAfter = waited.after
    pageSwitch = attribute
    return true
}

/// For a check: brings the app forward a moment for its page to be built,
/// runs `build` there, then brings back the app that was in front.
func inFront<T>(pid: pid_t, _ build: () -> T) -> T {
    let front = NSWorkspace.shared.frontmostApplication
    if let front, front.processIdentifier != pid { stopState.frontToRestore = front.bundleURL }
    bringForward(appURL)
    broughtForward = true
    let result = build()
    if let url = stopState.frontToRestore {
        bringForward(url)
        stopState.frontToRestore = nil
        // Its desktop slides away for about half a second, and the
        // frames read meanwhile are off (Spotify's Play: not in sight).
        Thread.sleep(forTimeInterval: 1)
    }
    return result
}

/// Whether the page shows a player's Play/Pause: a button in sight named
/// so, with a player's slider around it (no hit test: a quick look).
func showsPlayerBar(_ pid: pid_t) -> Bool {
    (pageButtons(pid: pid) ?? []).contains { $0.inSight && named($0.label, playPauseWords) && playerBar(of: $0.element) != nil }
}

/// For a check that found the page readable already but with no player's
/// Play/Pause in it: the page may be a leftover, so it's built again.
/// Electron drops part of its page when its switch goes off, and doesn't
/// keep it up to date out of sight: the user's first check of Deezer, on
/// another desktop some ten minutes after a press had turned its switch
/// off, found no page button, and later checks did (2026-10-11). The switch
/// goes off and on, and the player's bar is looked for up to 4 s; when it
/// doesn't show, the app is brought forward a moment, as `showPage` does
/// (once per check, as the user allowed), the switch turned off and on there.
func rebuildPage(with attribute: String, pid: pid_t) {
    func waitForBar(_ seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            Thread.sleep(forTimeInterval: 0.25)
            if showsPlayerBar(pid) { return true }
        } while Date() < deadline
        return false
    }
    func switchAgain() {
        _ = setSwitch(attribute, false, pid: pid)
        _ = setSwitch(attribute, true, pid: pid)
    }
    say("  no player's Play/Pause in it: it may be a leftover, so it's built again (\(switchName(attribute)) turned off and on)")
    let start = Date()
    switchAgain()
    if waitForBar(4) {
        say(String(format: "  its player bar showed after %.1f s", Date().timeIntervalSince(start)))
        return
    }
    let shown = inFront(pid: pid) {
        switchAgain()
        return waitForBar(6)
    }
    say("  not in place: brought it forward a moment, with the switch turned off and on there"
        + (shown ? String(format: "; its player bar showed (%.1f s in all)", Date().timeIntervalSince(start))
                 : "; still no player's Play/Pause"))
}

/// Set by a press when its page didn't show with the switch on: an
/// Electron, CEF or Flutter app builds it only while its window can be seen,
/// and a press doesn't bring it forward.
var pageOutOfView = false

/// Why a press by the page didn't work, and what to try instead.
func pagePressHint() -> String {
    "; an \(hiddenInterface.map { "app built with \($0.name)" } ?? "app") may build its page, or take presses on it, only while its"
        + " window is in view: bring it into view and try again, or use another way (AppleScript, its menu, or the Now Playing panel"
        + " as a last resort)"
}

// MARK: Where the player bar's button was (a press goes straight to it)

/// Where a player bar's button sits: the child indices from its page (an
/// AXWebArea) or, in a Flutter app, its window, down to it, so a press walks
/// straight to it instead of searching the page and hit-testing its buttons.
struct ButtonPath: Codable, Equatable {
    var root: String   // "page" or "window"
    var path: [Int]
}

/// What's kept of an app's page button between runs, per app (in
/// ~/Library/Caches/PlayerCheck/button-places.json): its `ButtonPath`, and,
/// once learned as AutoHush learns a web app's (`learnPageButton`), its
/// `PlayPauseRecipe`: the site's own words for Play and Pause, and where the
/// button is by the kinds of element around it and its distance from the
/// window's bottom, up to 3 layouts, which finds it again after its page
/// reloads (`PlayPauseRecipe.find`).
struct SavedButton: Codable {
    var path: ButtonPath?
    var recipe: SavedRecipe?
}
struct SavedRecipe: Codable {
    struct Place: Codable { var path: [String]; var fromBottom: Double }
    var play: String, pause: String, places: [Place]
    init(_ recipe: PlayPauseRecipe) {
        play = recipe.playLabel
        pause = recipe.pauseLabel
        places = recipe.places.map { Place(path: $0.path, fromBottom: $0.distanceFromBottom) }
    }
    var recipe: PlayPauseRecipe {
        PlayPauseRecipe(playLabel: play, pauseLabel: pause, places: places.map { ButtonPlace(path: $0.path, distanceFromBottom: $0.fromBottom) })
    }
}
let placesFile = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Caches/PlayerCheck/button-places.json")
func savedButtons() -> [String: SavedButton] {
    guard let data = try? Data(contentsOf: placesFile) else { return [:] }
    if let all = try? JSONDecoder().decode([String: SavedButton].self, from: data) { return all }
    // Before recipes: the paths alone.
    return ((try? JSONDecoder().decode([String: ButtonPath].self, from: data)) ?? [:]).mapValues { SavedButton(path: $0) }
}
func saveButton(_ change: (inout SavedButton) -> Void) {
    var all = savedButtons()
    var mine = all[bundleID] ?? SavedButton()
    change(&mine)
    all[bundleID] = mine
    try? FileManager.default.createDirectory(at: placesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? JSONEncoder().encode(all).write(to: placesFile)
}

/// The button's place, climbing from it to its page or window.
func placeOf(_ element: AXUIElement) -> ButtonPath? {
    var path: [Int] = [], node = element
    for _ in 0..<40 {
        let role = node.text(kAXRoleAttribute)
        if role == "AXWebArea" { return ButtonPath(root: "page", path: path.reversed()) }
        if role == kAXWindowRole { return isFlutter ? ButtonPath(root: "window", path: path.reversed()) : nil }
        guard let parent = node.value(kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
        let up = parent as! AXUIElement
        guard let index = up.children.firstIndex(where: { CFEqual($0, node) }) else { return nil }
        path.append(index)
        node = up
    }
    return nil
}

/// Remembers where the app's player bar's button is, when that changed.
func rememberPlace(of element: AXUIElement) {
    guard let found = placeOf(element), savedButtons()[bundleID]?.path != found else { return }
    saveButton { $0.path = found }
}

// MARK: Learning the page's Play/Pause, as AutoHush learns a web app's

/// AutoHush's own page reader, for a button's place and standing (`place`,
/// `standing`): any app's page, on any desktop, a Flutter app's items too.
let webPage = AccessibilityWebPage()
/// Learns the button whose words changed between a look while the app plays
/// and one once it paused (`PlayPauseLearner`), as AutoHush learns a web
/// app's from the user's It's Playing and It's Paused; here the pause is a
/// test's, by any way, or, with no other, the user's (`learnByUserPause`).
var learner = PlayPauseLearner()
/// The recipe learned in this run, and its button; the one learned before.
var learned: (recipe: PlayPauseRecipe, element: AXUIElement)?
let savedRecipe = savedButtons()[bundleID]?.recipe?.recipe
var learningSaid = false

/// The page's buttons as AutoHush's learning takes them, and their elements by handle.
func learningButtons(_ pid: pid_t) -> (buttons: [PageButton], elements: [ButtonHandle: AXUIElement]) {
    var elements: [ButtonHandle: AXUIElement] = [:]
    let buttons = (pageButtons(pid: pid) ?? []).map { found -> PageButton in
        let handle = ButtonHandle(found.element)
        elements[handle] = found.element
        return PageButton(handle: handle, label: found.label, isEnabled: found.element.value(kAXEnabledAttribute) as? Bool ?? true)
    }
    return (buttons, elements)
}

/// What a page button's words say of the state: by the learned recipe (the
/// site's own words), else this tool's lists ("Pause" while it plays).
func wordSays(_ words: String) -> PlayerState? {
    if let recipe = learned?.recipe ?? savedRecipe, let state = recipe.state(of: PageButton(handle: ButtonHandle(0), label: words)) {
        return state
    }
    return named(words, pauseWords) ? .playing : named(words, playWords) ? .paused : nil
}

/// Takes the look while it plays, once a test has it playing (`ready`).
func noteLearningPlaying(pid: pid_t) {
    guard page?.buttons ?? 0 > 0, !learner.hasPlayed, learned == nil else { return }
    learner.notePlaying(learningButtons(pid).buttons, at: Date())
}

/// Once a test paused it (by any way): the button whose words changed is
/// learned (`PlayPauseLearner.recipe`: in sight, with a player's controls,
/// the barest words, the lowest), saved merged with what was learned before,
/// and pressed by the page way from then on. Said once when nothing changed.
func learnPageButton(pid: pid_t) {
    guard learned == nil, learner.hasPlayed else { return }
    let (buttons, elements) = learningButtons(pid)
    let placed = learner.candidates(paused: buttons).compactMap { candidate in
        webPage.place(of: candidate.handle).flatMap { place in webPage.standing(of: candidate.handle).map { (candidate, place, $0) } }
    }
    guard let (recipe, handle) = PlayPauseLearner.recipe(from: placed), let element = elements[handle] else {
        if !learningSaid {
            learningSaid = true
            say("    its page's Play/Pause not learned: none of its buttons changed words"
                + (hiddenInterface != nil && page?.toggle?.onScreen == false ? " (a Chromium page out of sight keeps its words)" : ""))
        }
        return
    }
    let merged = savedRecipe?.merging(recipe) ?? recipe
    learned = (merged, element)
    saveButton { saved in
        saved.recipe = SavedRecipe(merged)
        if let path = placeOf(element) { saved.path = path }
    }
    let guess = page?.toggle
    let same = guess.map { CFEqual($0.element, element) }
    say("    learned its page's Play/Pause, as AutoHush learns a web app's: '\(recipe.pauseLabel)' while it plays, '\(recipe.playLabel)'"
        + " while paused, \(Int(recipe.places[0].distanceFromBottom)) pt from the window's bottom"
        + (same == true ? " (the button this tool found)" : guess.map { " (not '\($0.label)', the one this tool found)" } ?? ""))
    if same != true {
        let frame = element.frame
        page = PageCheck(buttons: page?.buttons ?? buttons.count,
                         toggle: FoundButton(element: element, label: label(of: element), fromBottom: recipe.places[0].distanceFromBottom,
                                             inSight: true, onScreen: guess?.onScreen ?? (frame != nil)),
                         withControls: placed.first { $0.0.handle == handle }?.2.isWithPlayerControls ?? false)
        barToggle = element
    }
}

/// After a press by the page that took: what the pressed button said before
/// and after it is learned, as AutoHush learns a button again once it went
/// missing, merged with what was learned before.
func learnFromPress(_ element: AXUIElement, before: String, pausing: Bool) {
    let after = label(of: element)
    guard !before.isEmpty, !after.isEmpty, before != after, let place = webPage.place(of: ButtonHandle(element)) else { return }
    let recipe = PlayPauseRecipe(playLabel: pausing ? after : before, pauseLabel: pausing ? before : after, places: [place])
    saveButton { $0.recipe = SavedRecipe($0.recipe.map { $0.recipe.merging(recipe) } ?? recipe) }
}

/// The player bar's button where it was last found, when it's still there:
/// at its path, saying the learned recipe's words (else named Play or Pause,
/// with a player's slider around it), in sight; else, with a recipe, found
/// among the page's buttons at a learned place, as AutoHush finds a learned
/// button after its page reloads (`PlayPauseRecipe.find`).
func rememberedBarButton(pid: pid_t) -> (button: FoundButton, byPlace: Bool)? {
    guard let saved = savedButtons()[bundleID] else { return nil }
    let recipe = saved.recipe?.recipe
    let (windows, onThisDesktop) = appWindows(of: pid)
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    let hidden = app.value(kAXHiddenAttribute) as? Bool == true
    for window in windows {
        guard let path = saved.path else { break }
        AXUIElementSetMessagingTimeout(window, 1)
        guard let windowFrame = window.frame else { continue }
        for root in path.root == "window" ? [window] : webAreas(in: window) {
            var node: AXUIElement? = root
            for index in path.path {
                let children = node?.children ?? []
                node = index < children.count ? children[index] : nil
            }
            guard let node, let frame = node.frame else { continue }
            let words = label(of: node)
            let says = recipe.map { $0.state(of: PageButton(handle: ButtonHandle(0), label: words)) != nil }
                ?? (named(words, playPauseWords) && playerBar(of: node) != nil)
            guard says, frame.width > 0, frame.height > 0, (windowFrame.minY...windowFrame.maxY).contains(frame.midY) else { continue }
            return (FoundButton(element: node, label: words, fromBottom: Double(windowFrame.maxY - frame.midY), inSight: true,
                                onScreen: onThisDesktop && !hidden && window.value(kAXMinimizedAttribute) as? Bool != true), false)
        }
    }
    guard let recipe, let all = pageButtons(pid: pid) else { return nil }
    let (buttons, elements) = (all.map { PageButton(handle: ButtonHandle($0.element), label: $0.label) },
                               Dictionary(all.map { (ButtonHandle($0.element), $0) }, uniquingKeysWith: { first, _ in first }))
    guard let found = recipe.find(in: buttons, place: webPage.place(of:)), let button = elements[found.handle] else { return nil }
    rememberPlace(of: button.element)
    return (button, true)
}

/// Whether the page was read: a press by the panel reads it only when its
/// row can't be told otherwise (`panelPress`).
var pageRead = false

/// For a press: takes the player bar's button where it was last time as
/// the page's Play/Pause, when it's still there (turning on the switch an
/// Electron, CEF or Flutter app needs, so the page stays up to date).
func useRememberedBar(pid: pid_t) -> Bool {
    guard let (found, byPlace) = rememberedBarButton(pid: pid) else { return false }
    if let hidden = hiddenInterface { pageSwitch = hidden.switches.first { turnOn($0, pid: pid, pageReadable: true) } }
    page = PageCheck(buttons: 1, toggle: found, withControls: true)
    barToggle = found.element
    pageRead = true
    pageNotChecked = nil
    say("  its player bar's '\(found.label)', " + (byPlace ? "found at its learned place (its page changed since)" : "where it was last time"))
    return true
}

/// Reads the app's page: its buttons and its player's Play/Pause, turning on
/// the switch an Electron, CEF or Flutter app needs first. A press goes
/// straight to the player bar's button where it was last time, when it's
/// still there.
func readPage() {
    pageRead = true
    pageNotChecked = nil
    if running == nil {
        say("  not checked: the app isn't running")
        pageNotChecked = "it isn't running"
    } else if !AXIsProcessTrusted() {
        say("  not checked: this tool (or the app running it) needs the Accessibility permission")
        pageNotChecked = "no Accessibility permission"
    } else if pressingOneWay, useRememberedBar(pid: running!.processIdentifier) {
        // A press: the player bar's button where it was last time.
    } else if let before = pageButtons(pid: running!.processIdentifier) {
        let pid = running!.processIdentifier
        if !isWebApp, hiddenInterface == nil, !hasWebPage(pid: pid) {
            say("  none: no web page in its windows, and not built with Electron, Chromium (CEF) or Flutter")
            pageNotChecked = "no page in its windows"
        } else {
            let items = isFlutter ? "pressable items" : "buttons"
            switch hiddenInterface {
            case let hidden?:
                say("  built with \(hidden.name): "
                    + (isFlutter ? "its interface (not a web page) shows" : "its page shows")
                    + " once a switch for assistive tools is on (" + hidden.switches.map(switchName).joined(separator: ", else ") + ")")
            case nil:
                say(isWebApp ? "  a Safari web app: WebKit shows its page as it is" : "  a web page in its windows: shown as it is")
            }
            var count = before.count
            var shownAfter: TimeInterval?
            var tookNone = false
            var readableAlready = false
            if count > 0, let hidden = hiddenInterface {
                // Shown to an assistive tool before (VoiceOver, or this tool):
                // a switch still goes on, so the app keeps the page up to date.
                say("  readable already: an assistive tool asked for it before")
                pageSwitch = hidden.switches.first { turnOn($0, pid: pid, pageReadable: true) }
                readableAlready = true
            } else if count == 0, let hidden = hiddenInterface {
                tookNone = true
                for attribute in hidden.switches {
                    guard let shown = showPage(with: attribute, pid: pid, count: &count, shownAfter: &shownAfter) else { continue }
                    tookNone = false
                    if shown { break }
                }
            } else if count == 0 {
                // A web page fills in once something first asks for it (YouTube
                // Music, just opened: 0 buttons at the first look, 36 a few
                // seconds later).
                let waited = waitForPage(pid, seconds: 8)
                count = waited.count
                shownAfter = waited.after
                if count == 0 { say("  its page showed no buttons in 8 s: is the site loaded?") }
            }
            if tookNone {
                pageNotChecked = "no switch was taken"
            } else if count == 0 {
                if hiddenInterface != nil { say("  no switch showed it: its \(items) can't be read this way") }
                page = PageCheck(buttons: 0, toggle: nil)
            } else {
                if readableAlready, action == nil, let attribute = pageSwitch, !showsPlayerBar(pid) {
                    rebuildPage(with: attribute, pid: pid)
                }
                let readStart = Date()
                let buttons = pageButtons(pid: pid) ?? []
                let readTime = Date().timeIntervalSince(readStart)
                let toggle = playerButton(pid: pid, named: playPauseWords)
                page = PageCheck(buttons: buttons.count, toggle: toggle?.button, withControls: toggle?.withControls ?? false)
                if let toggle, toggle.withControls {
                    barToggle = toggle.button.element
                    rememberPlace(of: toggle.button.element)
                }
                let with = pageSwitch.map { "  \(switchName($0)) on: its " } ?? "  its "
                say((shownAfter.map { String(format: "%@%@ showed %d %@ after %.1f s", with, isFlutter ? "interface" : "page", buttons.count, items, $0) }
                        ?? "\(with)\(isFlutter ? "interface" : "page"): \(buttons.count) \(items)")
                    + String(format: " (one read, as AutoHush reads a web app: %.0f ms)", readTime * 1000))
                if let (button, withControls) = toggle {
                    say(String(format: "  Play/Pause: '%@', %.0f pt from the window's bottom, ", button.label, button.fromBottom ?? 0)
                        + (withControls ? "with a player's slider around it" : "the lowest in sight (no slider around any)"))
                } else {
                    let near = Set(buttons.map(\.label).filter { label in playPauseWords.contains { label.lowercased().contains($0) } })
                    say("  none in sight named just Play or Pause" + (near.isEmpty ? "" : "; with those words: "
                        + near.sorted().prefix(8).map { "'\($0)'" }.joined(separator: ", ")))
                }
            }
        }
    } else {
        // Deezer keeps playing with its window closed, and its page can't be
        // read then, not even through windows on other desktops.
        say("  not checked: no window open on any desktop; open it and run again (a closed window's page can't be read)")
        pageNotChecked = "no window open"
    }
}

if !pressNeeds(["page"]) {
    say(via == "panel" ? "  not read yet: a press by the panel reads it only when its windows' titles and current track don't tell its row"
                       : "  not read: --via \(via!) doesn't need it")
    pageNotChecked = "not needed for --via \(via!)"
} else {
    readPage()
}

// MARK: - Press test

/// Why AppleScript can't be used, when macOS refuses it (no Automation permission).
var scriptProblem: String?

/// -1743: macOS refused the Apple event (the Automation permission).
func noteScriptError(_ number: Any?) {
    if (number as? Int) == -1743 {
        scriptProblem = "macOS doesn't let this tool (or the app running it) control \(appName) by AppleScript: allow it in System Settings → Privacy & Security → Automation"
    }
}

/// A four-character code as a number ("spfy" → 0x73706679).
func osType(_ text: String) -> FourCharCode {
    text.utf8.prefix(4).reduce(0) { $0 << 8 | FourCharCode($1) }
}

/// The object specifier for the property `code` of `container` (nil: the
/// application), as AppleScript builds one for "player state" or "name of
/// current track".
func propertySpecifier(_ code: String, of container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor {
    let specifier = NSAppleEventDescriptor.record().coerce(toDescriptorType: osType("obj "))!
    specifier.setDescriptor(NSAppleEventDescriptor(typeCode: osType("prop")), forKeyword: osType("want"))
    specifier.setDescriptor(container ?? NSAppleEventDescriptor.null(), forKeyword: osType("from"))
    specifier.setDescriptor(NSAppleEventDescriptor(enumCode: osType("prop")), forKeyword: osType("form"))
    specifier.setDescriptor(NSAppleEventDescriptor(typeCode: osType(code)), forKeyword: osType("seld"))
    return specifier
}

/// Whether macOS lets this tool (or the app running it) send the app Apple
/// events, asked once before the first, as AutoHush asks when a player is
/// chosen (`AutomationPermission`): a send waits only 5 s, too short for
/// someone reading macOS's prompt. Said once; denied, no event is sent.
var automationAnswer: AutomationPermission?
func automationAllowed(pid: pid_t) -> Bool {
    if automationAnswer == nil {
        let answer = AutomationPermission(status: AutomationPermission.check(pid: pid, ask: true))
        automationAnswer = answer
        // A press's output is its one line of result: there it's only logged.
        let note = action == nil ? say : log
        switch answer {
        case .allowed: note("  Automation for \(appName): allowed")
        case .denied, .notAsked:
            noteScriptError(-1743)
            note("  Automation for \(appName): not allowed: allow it in System Settings → Privacy & Security → Automation")
        case .notRunning: break
        }
    }
    return automationAnswer == .allowed
}

/// An Apple event error as AutoHush words it (`ScriptablePlayer.mapError`),
/// with macOS's number: "error -1743 (Automation permission … not granted)".
func eventError(_ error: NSError) -> String {
    let mapped = ScriptablePlayer.mapError(number: error.code, message: nil)
    if case .playerCommandFailed = mapped { return "error \(error.code)" }
    return "error \(error.code) (\(mapped.localizedDescription))"
}

/// Sends the app an Apple event as AutoHush's `AppleEventChannel` does: to
/// the running process, so an event can never launch the app, waiting
/// `AppleEventChannel.replyTimeout` (5 s) for the reply, after asking for
/// Automation once (`automationAllowed`). The reply's result, or the error
/// number (-1743: macOS refused it; -600: it isn't running).
func sendAppleEvent(_ code: String, directObject: NSAppleEventDescriptor? = nil,
                    parameters: [String: NSAppleEventDescriptor] = [:]) -> Result<NSAppleEventDescriptor?, NSError> {
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { !$0.isTerminated })?
        .processIdentifier else { return .failure(NSError(domain: NSOSStatusErrorDomain, code: -600)) }
    guard automationAllowed(pid: pid) else { return .failure(NSError(domain: NSOSStatusErrorDomain, code: -1743)) }
    let event = NSAppleEventDescriptor.appleEvent(withEventClass: osType(String(code.prefix(4))),
                                                  eventID: osType(String(code.suffix(4))),
                                                  targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                                                  returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    if let directObject { event.setParam(directObject, forKeyword: osType("----")) }
    for (keyword, value) in parameters { event.setParam(value, forKeyword: osType(keyword)) }
    do {
        let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: AppleEventChannel.replyTimeout)
        if let number = reply.paramDescriptor(forKeyword: osType("errn"))?.int32Value, number != 0 {
            return .failure(NSError(domain: NSOSStatusErrorDomain, code: Int(number)))
        }
        return .success(reply.paramDescriptor(forKeyword: osType("----")))
    } catch {
        return .failure(error as NSError)
    }
}

/// The object specifier for the app's documents: every one, or one by name
/// or by index (1: the front one), as AppleScript builds "document 1".
func documentSpecifier(named name: String? = nil, index: Int? = nil) -> NSAppleEventDescriptor {
    let specifier = NSAppleEventDescriptor.record().coerce(toDescriptorType: osType("obj "))!
    specifier.setDescriptor(NSAppleEventDescriptor(typeCode: osType(scripting?.documentClass ?? "docu")), forKeyword: osType("want"))
    specifier.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: osType("from"))
    if let name {
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: osType("name")), forKeyword: osType("form"))
        specifier.setDescriptor(NSAppleEventDescriptor(string: name), forKeyword: osType("seld"))
    } else {
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: osType("indx")), forKeyword: osType("form"))
        if let index {
            specifier.setDescriptor(NSAppleEventDescriptor(int32: Int32(index)), forKeyword: osType("seld"))
        } else {
            var all = osType("all ")
            specifier.setDescriptor(NSAppleEventDescriptor(descriptorType: osType("abso"), bytes: &all, length: 4)!,
                                    forKeyword: osType("seld"))
        }
    }
    return specifier
}

/// A reply's items: a list's, else the one value.
func items(_ descriptor: NSAppleEventDescriptor?) -> [NSAppleEventDescriptor] {
    guard let descriptor else { return [] }
    guard descriptor.descriptorType == osType("list") else { return [descriptor] }
    return descriptor.numberOfItems > 0 ? (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0) } : []
}

/// Its open documents by script (QuickTime Player's), front first: each
/// one's name and whether it's playing.
func scriptedDocuments() -> Result<[(name: String, playing: Bool)], NSError> {
    guard let playing = scripting?.documentPlaying else { return .success([]) }
    let every = documentSpecifier()
    switch (sendAppleEvent("coregetd", directObject: propertySpecifier("pnam", of: every)),
            sendAppleEvent("coregetd", directObject: propertySpecifier(playing, of: every))) {
    case (.failure(let error), _), (_, .failure(let error)):
        return .failure(error)
    case (.success(let names), .success(let flags)):
        return .success(zip(items(names), items(flags)).map { ($0.stringValue ?? "", $1.booleanValue) })
    }
}

/// The documents a test's pause paused, by name: its play plays them again.
var pausedDocuments: [String] = []

/// The app's state by script, when its dictionary has it and it answers:
/// its `player state` (stopped, playing, paused, as Spotify's), else its
/// `playing` flag (VLC's: playing or paused), else its documents' (QuickTime
/// Player's: playing while one is, stopped with none open), asked by Apple
/// event. Only macOS refusing it (-1743: no Automation permission for
/// whatever runs this tool) stops the asking; another error (a timeout,
/// -1712, from a busy VLC) counts for that look only. Each kind of error is
/// said once.
var scriptError: Any?
var scriptErrorsSaid: Set<String> = []
func scriptedState() -> String? {
    guard let scripting, scripting.hasState, scriptError == nil else { return nil }
    func failed(_ error: NSError) -> String? {
        noteScriptError(error.code)
        let refused = error.code == -1743
        if refused { scriptError = error.code }
        if scriptErrorsSaid.insert("\(error.code)").inserted {
            say("  its state can't be read by script: \(eventError(error))" + (refused ? "" : " (asked again at the next look)"))
        }
        return nil
    }
    if !scripting.hasPlayerState, !scripting.hasPlayingFlag {
        switch scriptedDocuments() {
        case .failure(let error): return failed(error)
        case .success(let documents): return documents.isEmpty ? "stopped" : documents.contains(where: \.playing) ? "playing" : "paused"
        }
    }
    let property = scripting.hasPlayerState ? "pPlS" : scripting.properties.first { $0.value == "playing" }!.key
    switch sendAppleEvent("coregetd", directObject: propertySpecifier(property)) {
    case .failure(let error):
        return failed(error)
    case .success(let result):
        guard let result else { return nil }
        guard scripting.hasPlayerState else {
            if result.booleanValue { return "playing" }
            // Not playing: VLC's `current time` is -1 with no item, so it's
            // stopped, else paused, as AutoHush's VLCPlayer tells them apart.
            guard let time = scripting.properties.first(where: { $0.value == "current time" })?.key,
                  case .success(let reply?) = sendAppleEvent("coregetd", directObject: propertySpecifier(time))
            else { return "paused" }
            let state = VLCPlayer.state(playing: false, currentTime: Int(reply.int32Value))
            return state == .unknown ? "paused" : state.rawValue
        }
        let states: [String: String] = ["kPSP": "playing", "kPSp": "paused", "kPSS": "stopped",
                                        "kPSF": "fast forwarding", "kPSR": "rewinding"]
        let code = result.enumCodeValue
        let text = String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, encoding: .macOSRoman) ?? "?"
        return states[text] ?? text
    }
}

/// The name of what it plays, by Apple event, when its dictionary has a
/// `current track` (Spotify's, Music's, TV's). It stays while paused, where
/// a window's title may not (a paused Spotify's says "Spotify Premium").
/// Nil without one, or when it doesn't answer (nothing loaded).
func scriptedSong() -> String? {
    guard let scripting, scripting.hasCurrentTrack, scriptError == nil else { return nil }
    switch sendAppleEvent("coregetd", directObject: propertySpecifier("pnam", of: propertySpecifier("pTrk"))) {
    case .failure(let error):
        noteScriptError(error.code)
        return nil
    case .success(let result):
        return result?.stringValue
    }
}

/// Sends the app one of its dictionary's commands (by name: "pause", "play",
/// "playpause"), as an Apple event; false (and why) when it fails. One that
/// acts on a document (QuickTime Player's) goes to each playing one for a
/// pause or stop, and for a play to those a test paused, else the front one.
func sendScript(_ command: String) -> Bool {
    guard let code = scripting?.commandCode(command) else {
        say("    \(command): not in its dictionary")
        return false
    }
    func failed(_ error: NSError) -> Bool {
        noteScriptError(error.code)
        say("    \(command): \(eventError(error))")
        return false
    }
    guard scripting?.documentCommands.contains(code) == true else {
        if case .failure(let error) = sendAppleEvent(code) { return failed(error) }
        return true
    }
    let documents: [(name: String, playing: Bool)]
    switch scriptedDocuments() {
    case .failure(let error): return failed(error)
    case .success(let found): documents = found
    }
    let stopping = ["pause", "stop"].contains(command.lowercased())
    var targets: [NSAppleEventDescriptor]
    if stopping {
        let playing = documents.filter(\.playing).map(\.name)
        if command.lowercased() == "pause" { pausedDocuments = playing }
        targets = playing.map { documentSpecifier(named: $0) }
    } else {
        let paused = pausedDocuments.filter { name in documents.contains { $0.name == name } }
        targets = paused.map { documentSpecifier(named: $0) }
        if targets.isEmpty, !documents.isEmpty { targets = [documentSpecifier(index: 1)] }
        pausedDocuments = []
    }
    guard !targets.isEmpty else {
        say("    \(command): no document \(stopping ? "playing" : "open")")
        return false
    }
    for target in targets {
        if case .failure(let error) = sendAppleEvent(code, directObject: target) { return failed(error) }
    }
    return true
}

/// Whether its volume can be read and set as fades need it, checked once
/// while a test has it paused (silent): its `sound volume` (Spotify's,
/// Music's), else its `audio volume` (VLC's, 0–512), set one step away and
/// read back, then put back. An app that reads back another number than it
/// was set to (Spotify: one less) needs the profile's `readVolume`, or each
/// fade restoring the volume it read loses a step.
var volumeChecked = false
func checkVolume() {
    guard !volumeChecked, let scripting,
          let (code, name) = scripting.properties.first(where: { $0.value == "sound volume" })
              .map({ ($0.key, $0.value) }) ?? scripting.properties.first(where: { $0.value == "audio volume" }).map({ ($0.key, $0.value) })
    else { return }
    volumeChecked = true
    func read() -> Int? {
        guard case .success(let reply?) = sendAppleEvent("coregetd", directObject: propertySpecifier(code)) else { return nil }
        return Int(reply.int32Value)
    }
    func set(_ value: Int) -> NSError? {
        if case .failure(let error) = sendAppleEvent("coresetd", directObject: propertySpecifier(code),
                                                     parameters: ["data": NSAppleEventDescriptor(int32: Int32(value))]) { return error }
        return nil
    }
    guard let start = read() else { say("    volume ('\(name)'): can't be read: no fades"); return }
    let target = start > 1 ? start - 1 : start + 1
    if let error = set(target) { say("    volume ('\(name)'): \(start), can't be set (\(eventError(error))): no fades"); return }
    // Music drops a change that follows another within a moment (measured:
    // set 99 then 100 at once, it stays at 99; 0.2 s apart, it takes both).
    Thread.sleep(forTimeInterval: 0.3)
    guard let back = read() else { say("    volume ('\(name)'): set to \(target), then can't be read: no fades"); return }
    let offset = back - target
    // Put back as it was: an app that reads one less is set one more.
    var restored: Int?
    for _ in 0..<2 where restored != start {
        _ = set(start - offset)
        Thread.sleep(forTimeInterval: 0.3)
        restored = read()
    }
    say("    volume ('\(name)'): \(start); set to \(target), it reads \(back): "
        + (offset == 0 ? "reads back as set, so it can fade"
           : "reads \(abs(offset)) \(offset < 0 ? "less" : "more") than set (as Spotify, one less): the profile needs readVolume")
        + (restored == start ? "; put back to \(start)" : "; couldn't put it back: it reads \(restored.map(String.init) ?? "?") (was \(start))")
        + (name == "audio volume" ? " (its own scale: VLC's goes to 512)" : ""))
}

/// Its AppleScript commands to pause and play it: pause and play in its own
/// suite (what ScriptablePlayers needs), else commands named so, else one
/// that toggles (playpause, or VLC's play, which toggles).
func scriptControls() -> (pause: String, play: String, toggles: Bool)? {
    guard let scripting else { return nil }
    if let suite = scripting.suite, let pause = scripting.commands[suite + "Paus"], let play = scripting.commands[suite + "Play"] {
        return (pause, play, false)
    }
    let names = Set(scripting.commands.values.map { $0.lowercased() })
    if names.contains("pause"), names.contains("play") { return ("pause", "play", false) }
    if names.contains("playpause") { return ("playpause", "playpause", true) }
    if names.contains("play") { return ("play", "play", true) }
    return nil
}

/// The usual names of a player's state notification: Spotify's
/// `<bundle ID>.PlaybackStateChanged`, Music's `<bundle ID>.playerInfo`, and
/// their likely variants. macOS delivers a distributed notification only to
/// observers that name it (one with no name gets nothing, measured on macOS
/// 27), so a name outside this list can't be seen.
let stateNotificationSuffixes = ["PlaybackStateChanged", "playbackStateChanged", "playerInfo", "PlayerInfo",
                                 "PlayerStateChanged", "playerStateChanged", "PlayStateChanged", "playStateChanged"]

/// The state notifications seen, with their userInfo keys, and what each
/// announced: the state in its "Player State", as AutoHush's ScriptablePlayers
/// read it (`PlayerStateObserver`), which is how AutoHush follows such a
/// player instead of asking it. Delivered while the run loop runs.
final class NotificationLog: NSObject {
    var seen: [String: Set<String>] = [:]
    /// Each one with a state, in order: its name, the state, when.
    private(set) var announcements: [(name: String, state: PlayerState, at: Date)] = []
    init(bundleID: String) {
        super.init()
        for suffix in stateNotificationSuffixes {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(note(_:)), name: Notification.Name("\(bundleID).\(suffix)"), object: nil,
                suspensionBehavior: .deliverImmediately)
        }
    }
    @objc func note(_ notification: Notification) {
        seen[notification.name.rawValue, default: []].formUnion((notification.userInfo ?? [:]).keys.map { "\($0)" })
        let state = PlayerStateObserver.playerState(from: notification.userInfo)
        if state != .unknown { announcements.append((notification.name.rawValue, state, Date())) }
    }
    /// What was announced since `date`, in order.
    func announced(since date: Date) -> [(name: String, state: PlayerState, at: Date)] {
        announcements.filter { $0.at >= date }
    }
    /// The last state announced since `date`; Music posts each change twice,
    /// the state before, then the new one.
    func lastState(since date: Date) -> PlayerState? { announced(since: date).last?.state }
}

/// The notification that announced both a trial's pause and its play: what
/// a ScriptablePlayerProfile names (`stateNotification`).
var announcingNotification: String?

/// What the notifications announced since `date`, for a trial's line.
func announcementLine(since date: Date) -> String? {
    guard let notifications else { return nil }
    let said = notifications.announced(since: date)
    // Silence is worth saying only of an app AutoHush would follow by its notification.
    guard !said.isEmpty else { return scripting?.fitsScriptablePlayer == true ? "    notifications: none announced it" : nil }
    return "    announced: " + said.map { $0.state.rawValue }.joined(separator: ", then ") + " (\(said.last!.name))"
}

/// The page's Play/Pause in its player bar, found last (`barToggle`): read
/// again by its words alone, as a full search reads the whole page and
/// hit-tests its buttons. A song's own button (no player bar around it)
/// isn't kept: a bar may show up once something plays. Without one, the
/// full search runs at most every 2 s.
func pageToggleLabel(_ pid: pid_t) -> String? {
    if let element = barToggle {
        let words = label(of: element)
        if wordSays(words) != nil { return words }
        barToggle = nil // gone, or redrawn as another element
    }
    guard Date().timeIntervalSince(lastSearch) >= 2 else { return lastSearchLabel }
    let found = playerButton(pid: pid, named: playPauseWords)
    if let found, found.withControls {
        barToggle = found.button.element
        return found.button.label
    }
    lastSearch = Date()
    lastSearchLabel = found?.button.label
    return lastSearchLabel
}

/// What can be seen of whether it plays: the menu's first item, its
/// scripted state, what it reports to Now Playing, its page's Play/Pause,
/// its sound output, its level (when measured) and its keep-awake assertion.
struct Look: Equatable {
    var menuTitle: String?
    /// As its menu's item tells it (`menuState`): stopped while disabled.
    var menuState: String?
    var state: String?
    var reported: String?
    var pageToggle: String?
    var sounding: Bool
    /// Heard by its level; nil when not measured.
    var audible: Bool? = nil
    /// As its keep-awake assertions tell it (`awake`); nil while they don't.
    var awake: Bool? = nil
    var line: String {
        [menuTitle.map { "menu '\($0)'" + (menuState == "stopped" ? " (disabled)" : "") }, state.map { "state \($0)" }, reported.map { "reports \($0.lowercased())" },
         pageToggle.map { "page '\($0)'" }, "sound \(sounding ? "on" : "off")",
         audible.map { $0 ? "heard" : "silent" }, awake.map { $0 ? "keeps the Mac awake" : "no keep-awake assertion" }]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

func look(_ pid: pid_t, level: Bool = false) -> Look {
    // The log is read only for an app with no scripted state (its own is
    // surer), and, for a press, only while its player bar isn't on screen.
    let state = scriptedState()
    let toggle = menu == nil ? nil : menuToggle(pid: pid)
    let sounding = !soundProcesses(of: pid).isEmpty
    return Look(menuTitle: toggle?.title, menuState: toggle.flatMap(menuState), state: state,
                reported: state == nil && !barShowsState ? reportedState() : nil,
                pageToggle: page?.toggle == nil ? nil : pageToggleLabel(pid),
                sounding: sounding, audible: level ? audible(pid) : nil, awake: awake(pid, sounding: sounding))
}

/// For a press, whether its page's player bar shows the app's state by its
/// button's word: on screen (this desktop, not hidden or minimised), or,
/// for a WebKit page, anywhere. Then what it reports to Now Playing isn't
/// read (opening macOS's log and reading back to when the app opened:
/// 1.4–2 s). An Electron page on another desktop keeps a stale word, so
/// there the log is read.
var barShowsState: Bool {
    pressingOneWay && page?.withControls == true && (page?.toggle?.onScreen == true || pageIsWebKit)
}

/// Whether its page is Safari's WebKit: a Safari web app's, or the app's
/// own (a Tauri app's, as Pake's YouTube Music), and not Chromium inside Qt
/// (Qt WebEngine). Out of sight, WebKit keeps its words current: Pake's
/// YouTube Music and SoundCloud's web app, on another desktop, showed each
/// change within 0.5 s, also after minutes there (2026-10-11).
let pageIsWebKit: Bool = {
    if isWebApp { return true }
    guard hiddenInterface == nil, let binary = Bundle(url: appURL)?.executableURL,
          linkedFrameworks(binary).contains("WebKit") else { return false }
    let frameworks = (try? FileManager.default.contentsOfDirectory(atPath: appURL.appendingPathComponent("Contents/Frameworks").path)) ?? []
    return !frameworks.contains { $0.hasPrefix("QtWebEngine") }
}()

/// A look for a press's `Sign`: its level is measured (half a second) only
/// when nothing surer shows the state, so presses stay quick.
func lookForSign(_ pid: pid_t) -> Look {
    let quick = look(pid)
    guard levelsAllowed, quick.state == nil, quick.reported == nil, quick.pageToggle == nil else { return quick }
    return look(pid, level: true)
}

/// Waits up to `seconds`, running the run loop (for notifications), until
/// `done` holds (or a stop is asked), then a second more for late
/// notifications; the last look (its level measured when `level`).
func waitFor(_ seconds: Double, pid: pid_t, level: Bool = false, until done: (Look) -> Bool) -> Look {
    let deadline = Date().addingTimeInterval(seconds)
    var current = look(pid, level: level)
    while !done(current), Date() < deadline, !stopState.isRequested {
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        current = look(pid, level: level)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    return current
}

/// How a trial went: it paused and played again, it only paused, or it
/// didn't pause.
enum TrialResult { case worked, pausedOnly, didNotPause }

/// Whether a press took, judged by the surest sign the app had before it:
/// its scripted state, else what it reports to Now Playing, else its page's
/// button (Play while paused), else its level (as AutoHush hears it), else
/// its keep-awake assertion (as AntiDot mode reads it), else its menu's
/// state (as AutoHush's MenuPlayer reads it), else its menu's word changing
/// or its sound. (Deezer's menu word changes late by itself: it said Play
/// while playing, then Pause a second later, with nothing pressed.)
struct Sign {
    let before: Look
    var byState: Bool { before.state != nil }
    var byReport: Bool { !byState && before.reported != nil }
    var byPage: Bool { !byState && !byReport && before.pageToggle != nil }
    var byLevel: Bool { !byState && !byReport && !byPage && before.audible != nil }
    var byAwake: Bool { !byState && !byReport && !byPage && !byLevel && before.awake != nil }
    var byMenu: Bool { !byState && !byReport && !byPage && !byLevel && !byAwake && before.menuState != nil }
    func paused(_ now: Look) -> Bool {
        if byState { return now.state != nil && now.state != "playing" }
        if byReport { return now.reported != nil && now.reported != "Playing" }
        if byPage { return now.pageToggle.map { wordSays($0) == .paused } ?? false }
        if byLevel { return now.audible == false }
        if byAwake { return now.awake == false }
        if byMenu { return now.menuState != nil && now.menuState != "playing" }
        return now.menuTitle != before.menuTitle || !now.sounding
    }
    func playing(_ now: Look) -> Bool {
        if byState { return now.state == "playing" }
        if byReport { return now.reported == "Playing" }
        if byPage { return now.pageToggle.map { wordSays($0) == .playing } ?? false }
        if byLevel { return now.audible == true }
        if byAwake { return now.awake == true }
        if byMenu { return now.menuState == "playing" }
        return now.sounding
    }
}

/// Pauses with `pause`, sees whether it took (`Sign`), plays again with
/// `play` if it did; `undo` runs when it didn't (a press that may have hit
/// another app), `whilePaused` between a pause that took and the play (to
/// learn the page's button, or check the volume, while it's silent). What
/// the state notifications announced is said after each. A stop meanwhile
/// waits until it plays again.
func trial(_ label: String, pid: pid_t, pause: () -> Bool, play: () -> Bool, undo: (() -> Void)? = nil,
           whilePaused: (() -> Void)? = nil) -> TrialResult {
    stopState.setInTrial(true)
    defer { stopState.setInTrial(false) }
    let before = look(pid, level: true)
    let sign = Sign(before: before)
    let paused = sign.paused, playing = sign.playing
    say("  \(label): before, \(before.line)")
    let pausedAt = Date()
    guard pause() else { say("    couldn't send it"); return .didNotPause }
    let after = waitFor(4, pid: pid, level: sign.byLevel, until: paused)
    guard paused(after) else {
        say("    after the pause: \(after.line) → it didn't pause in 4 s")
        announcementLine(since: pausedAt).map { say($0) }
        undo?()
        return .didNotPause
    }
    say("    after the pause: \(after.line) → it paused")
    announcementLine(since: pausedAt).map { say($0) }
    let pauseAnnounced = notifications?.announced(since: pausedAt).last.flatMap { $0.state == .playing ? nil : $0.name }
    whilePaused?()
    let playedAt = Date()
    guard play() else {
        say("    couldn't play it again")
        return .pausedOnly
    }
    let back = waitFor(4, pid: pid, level: sign.byLevel, until: playing)
    let again = playing(back)
    say("    after playing again: \(back.line) → " + (again ? "it plays" : "it didn't play again in 4 s"))
    announcementLine(since: playedAt).map { say($0) }
    if let pauseAnnounced, notifications?.announced(since: playedAt).last.map({ $0.state == .playing && $0.name == pauseAnnounced }) == true {
        announcingNotification = announcingNotification ?? pauseAnnounced
    }
    return again ? .worked : .pausedOnly
}

/// Whether it plays, as far as can be seen, in `Sign`'s order: its scripted
/// state, else what it reports to Now Playing, else its page's button (Pause
/// while it plays), else its level, else its keep-awake assertion, else its
/// menu's state, else its sound output (which an Electron app or a web app
/// keeps a few seconds after a pause, VLC a minute).
func isPlaying(_ pid: pid_t) -> Bool {
    let now = look(pid)
    if let state = now.state { return state == "playing" }
    if let reported = now.reported { return reported == "Playing" }
    if let toggle = now.pageToggle { return wordSays(toggle) == .playing }
    if let heard = audible(pid) { return heard }
    if let awake = now.awake { return awake }
    if let menu = now.menuState { return menu == "playing" }
    return now.sounding
}

/// Waits until it plays, asking whoever runs the tool to start it (the
/// Player Check app shows the "waiting:" line as a request): true once it
/// plays, false after `seconds`.
func waitUntilPlaying(_ pid: pid_t, seconds: Double = 120) -> Bool {
    if isPlaying(pid) { return true }
    say("  waiting: start playing something in \(appName); the test goes on as soon as it plays (up to \(Int(seconds / 60)) minutes)")
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if isPlaying(pid) {
            say("  it plays: testing")
            RunLoop.main.run(until: Date().addingTimeInterval(1.5)) // it settles, and reports to Now Playing
            return true
        }
    }
    return false
}

/// Whether the app (or a helper that plays for it) is the Now Playing one;
/// else which app is (or that MediaRemote didn't answer).
func nowPlayingHolder(_ pid: pid_t) -> (isThisApp: Bool, other: String) {
    let holder = nowPlayingPID()
    let other = holder < 0 ? "MediaRemote didn't answer" : holder == 0 ? "no app is"
        : (NSRunningApplication(processIdentifier: responsible(holder))?.localizedName ?? "pid \(holder)") + " is"
    return (holder > 0 && (holder == pid || responsible(holder) == pid), other)
}

// MARK: Whether it can report to Now Playing

/// The frameworks a Mach-O file links ("MediaPlayer" for
/// /System/Library/Frameworks/MediaPlayer.framework/…), from its load
/// commands: the arm64 slice of a universal file, else its first; empty
/// for a file that isn't 64-bit Mach-O.
func linkedFrameworks(_ url: URL) -> Set<String> {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
    defer { try? handle.close() }
    func read(_ offset: UInt64, _ count: Int) -> Data? {
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        return data
    }
    func word(_ data: Data, _ offset: Int, bigEndian: Bool = false) -> UInt32 {
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        return bigEndian ? UInt32(bigEndian: value) : value
    }
    guard let head = read(0, 8) else { return [] }
    var slice: UInt64 = 0
    switch word(head, 0) {
    case 0xbeba_feca, 0xbfba_feca: // universal (FAT_MAGIC, FAT_MAGIC_64, big-endian)
        let wide = word(head, 0) == 0xbfba_feca
        let count = Int(word(head, 4, bigEndian: true)), size = wide ? 32 : 20
        guard (1...16).contains(count), let table = read(8, count * size) else { return [] }
        var chosen: UInt64?
        for index in 0..<count {
            let base = index * size
            let offset = wide ? UInt64(word(table, base + 8, bigEndian: true)) << 32 | UInt64(word(table, base + 12, bigEndian: true))
                              : UInt64(word(table, base + 8, bigEndian: true))
            if word(table, base, bigEndian: true) == 0x0100_000c { chosen = offset; break } // arm64
            if chosen == nil { chosen = offset }
        }
        slice = chosen ?? 0
    case 0xfeed_facf: break // MH_MAGIC_64
    default: return []
    }
    guard let header = read(slice, 32), word(header, 0) == 0xfeed_facf else { return [] }
    let commands = Int(word(header, 16)), size = Int(word(header, 20))
    guard size < 1 << 22, let table = read(slice + 32, size) else { return [] }
    // LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_LAZY_LOAD_DYLIB, LC_LOAD_UPWARD_DYLIB
    let linking: Set<UInt32> = [0xc, 0x8000_0018, 0x8000_001f, 0x20, 0x8000_0023]
    var names = Set<String>()
    var offset = 0
    for _ in 0..<commands {
        guard offset + 12 <= table.count else { break }
        let length = Int(word(table, offset + 4))
        guard length >= 12, offset + length <= table.count else { break }
        if linking.contains(word(table, offset)) {
            let start = offset + Int(word(table, offset + 8))
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

/// Why an app can be in Now Playing, from what it's built with; nil when
/// nothing shows it can. An app gets in through MediaPlayer
/// (MPNowPlayingInfoCenter and MPRemoteCommandCenter, the public way;
/// Chromium and Electron use it too), MediaRemote (Apple's apps), AVKit's
/// player view (a video it plays), or WebKit: the pages any app shows report
/// through WebKit's GPU process, under the app's bundle ID (Safari's web
/// apps; Pake's YouTube Music, a Tauri app linking only WebKit, was the
/// active Now Playing app while it played). So: the frameworks its binaries
/// link, those in Contents/MacOS (VLC's is a plugin there) and its own
/// frameworks'. The Player Check app lists the apps by it
/// (`--now-playing-reasons`).
func nowPlayingReason(of url: URL, bundleID: String?) -> String? {
    if bundleID?.hasPrefix("com.apple.Safari.WebApp.") == true { return "WebKit, as a Safari web app" }
    if bundleID == "com.apple.Safari" || bundleID?.hasPrefix("com.apple.SafariTechnologyPreview") == true { return "WebKit" }
    var binaries: [URL] = []
    if let items = FileManager.default.enumerator(at: url.appendingPathComponent("Contents/MacOS"), includingPropertiesForKeys: [.isRegularFileKey]) {
        for case let item as URL in items where (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            binaries.append(item)
        }
    }
    for framework in (try? FileManager.default.contentsOfDirectory(at: url.appendingPathComponent("Contents/Frameworks"),
                                                                    includingPropertiesForKeys: nil)) ?? []
    where framework.pathExtension == "framework" {
        binaries.append(framework.appendingPathComponent(framework.deletingPathExtension().lastPathComponent))
    }
    var mediaPlayerIn: String?
    var others = Set<String>()
    for binary in binaries {
        let linked = linkedFrameworks(binary)
        if linked.contains("MediaPlayer"), mediaPlayerIn == nil { mediaPlayerIn = binary.lastPathComponent }
        others.formUnion(linked.intersection(["MediaRemote", "AVKit", "WebKit"]))
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
    if others.contains("WebKit") { return "WebKit, for the pages it shows" }
    return nil
}

/// Whether anything in it can report to Now Playing (so it may have a row
/// in the Now Playing panel, and report its state).
let canBeNowPlaying = nowPlayingReason(of: appURL, bundleID: bundleID) != nil

// MARK: What it reports to Now Playing

/// What an app reports to Now Playing itself, from the lines MediaRemote's
/// daemon writes in macOS's log (each "PlaybackState changed from … to …"),
/// as `--now-playing-list` reads them. A log store opened is a snapshot
/// (later lines don't show in it, and each opening takes about 0.6 s), so
/// the past is read once from one, back to `start`, and what follows comes
/// live from `log stream`, started first so nothing falls between.
final class ReportedState: @unchecked Sendable {
    private let appID: String
    private let lock = NSLock()
    private var clients: [pid_t: NowPlayingClient] = [:]
    private var buffer = Data()
    /// The stream ended: what's known may be old, so nothing is said.
    private var ended = false

    /// Nil when the log can't be read (it needs an administrator).
    init?(appID: String, since start: Date) {
        self.appID = appID
        let stream = Process()
        stream.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        stream.arguments = ["stream", "--style", "ndjson", "--predicate",
                            #"process == "mediaremoted" AND (composedMessage CONTAINS "nowPlayingClient" OR composedMessage CONTAINS "PlaybackState changed")"#]
        let pipe = Pipe()
        stream.standardOutput = pipe
        stream.standardError = FileHandle.nullDevice
        // At its end (the stream ended, or this tool stopped it) the handler
        // would be called again and again with nothing: it's removed.
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                self?.lock.withLock { self?.ended = true }
                return
            }
            self?.take(data)
        }
        guard (try? stream.run()) != nil, let store = try? OSLogStore.local() else {
            pipe.fileHandleForReading.readabilityHandler = nil
            if stream.isRunning { stream.terminate() }
            return nil
        }
        stopState.streamPID = stream.processIdentifier
        atexit { if stopState.streamPID > 0 { kill(stopState.streamPID, SIGTERM) } }
        var past: [pid_t: NowPlayingClient] = [:]
        _ = readNowPlayingLog(store, from: start, into: &past)
        // What came live meanwhile is newer, but only for what it says: a
        // live line with no state (a client created again) keeps the state
        // read from the past.
        lock.withLock {
            clients.merge(past) { live, old in
                var client = live
                if client.state == nil { client.state = old.state; client.changed = old.changed }
                if client.name.isEmpty { client.name = old.name }
                if old.id.count > client.id.count { client.id = old.id }
                return client
            }
        }
    }

    /// Lines from `log stream`, one JSON object each.
    private func take(_ data: Data) {
        lock.withLock {
            buffer.append(data)
            while let end = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<end]
                buffer.removeSubrange(buffer.startIndex...end)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let message = object["eventMessage"] as? String else { continue }
                applyNowPlayingLine(message, at: Date(), to: &clients)
            }
        }
    }

    /// Its latest state ("Playing", "Paused", "Stopped"…): the latest of its
    /// processes still there (a web app's is WebKit's media process); nil
    /// while none of them reported one, or once the stream ended.
    var state: String? {
        lock.withLock {
            guard !ended else { return nil }
            return clients.values
                .filter { $0.appID == appID && $0.state != nil && !$0.removed && (kill($0.pid, 0) == 0 || errno == EPERM) }
                .max { ($0.changed ?? .distantPast) < ($1.changed ?? .distantPast) }?.state
        }
    }
}

var reportedTracker: ReportedState?
var reportedTrackerMade = false

/// Whether the app plays as it reports to Now Playing, the surest sign
/// after its AppleScript state: it holds wherever its window is (an
/// Electron app's page on another desktop keeps the word it had, Play
/// while Deezer played). Read back to when the app opened, an hour at
/// most. Nil for an app that can't report to Now Playing, when the log
/// can't be read, or while it reported nothing since then.
func reportedState() -> String? {
    guard canBeNowPlaying, let running else { return nil }
    if !reportedTrackerMade {
        reportedTrackerMade = true
        reportedTracker = ReportedState(appID: bundleID, since: max(running.launchDate ?? .distantPast, Date().addingTimeInterval(-3600)))
    }
    return reportedTracker?.state
}

/// Presses a page button, as AutoHush's web apps press theirs: never one the
/// site disabled (during an ad, it can't be paused: AutoHush mutes the app
/// instead, which a one-off press can't hold); `why` says so.
func pressPageButton(_ button: FoundButton, pausing: Bool, why: inout String?) -> Bool {
    if button.element.value(kAXEnabledAttribute) as? Bool == false {
        why = "its page's '\(button.label)' is disabled (sites disable it during ads): not pressed"
            + (pausing ? "; AutoHush would mute it instead" : "")
        return false
    }
    return AXUIElementPerformAction(button.element, kAXPressAction as CFString) == .success
}

/// The page's button to press to pause (or play): the player bar's button
/// with that word; else, when the app's state is known (by script, else as
/// it reports to Now Playing), the bar's button whatever its word, since it
/// toggles (a Chromium page on another desktop keeps its word: Play while
/// it plays); else one with that word.
func pageButtonToPress(pid: pid_t, pausing: Bool) -> FoundButton? {
    let wanted: PlayerState = pausing ? .playing : .paused // what its words say when it's the one to press
    // The button learned in this run, as AutoHush presses a web app's: when
    // its words say what's wanted, or it toggles while a surer sign tells how it is.
    if let learned {
        let words = label(of: learned.element)
        let says = learned.recipe.state(of: PageButton(handle: ButtonHandle(0), label: words))
        if says == wanted || (says != nil && (scriptedState() != nil || reportedState() != nil)) {
            return FoundButton(element: learned.element, label: words, fromBottom: nil, inSight: true, onScreen: page?.toggle?.onScreen ?? true)
        }
    }
    // A press takes the player bar's button the page section found (where
    // it was last time, or at its learned place), read again by its words
    // (no new search, no hit tests): when it says what's wanted, or toggles
    // while the app reports how it is.
    if pressingOneWay, page?.withControls == true, let bar = page?.toggle {
        let words = label(of: bar.element)
        let found = FoundButton(element: bar.element, label: words, fromBottom: bar.fromBottom, inSight: bar.inSight, onScreen: bar.onScreen)
        if wordSays(words) == wanted { return found }
        if !barShowsState, wordSays(words) != nil, scriptedState() != nil || reportedState() != nil { return found }
    }
    let named = playerButton(pid: pid, named: pausing ? pauseWords : playWords)
    if let named, named.withControls { return named.button }
    if scriptedState() != nil || reportedState() != nil, let bar = playerButton(pid: pid, named: playPauseWords), bar.withControls {
        return bar.button
    }
    return named?.button
}
let notNowPlaying = "nothing in it reports to Now Playing, so the Now Playing panel can't reach it"
let panelNotNowPlaying = "nothing in it reports to Now Playing, so it has no row in the panel"

// MARK: The menu bar's Now Playing panel

/// One app's row in the menu bar's Now Playing panel (Control Center's): its
/// text ("Song, Artist – Album", or the app's name) and its Play/Pause.
struct PanelRow {
    let text: String
    let button: AXUIElement
    /// Read while the panel is open: its elements answer nothing once it closes.
    let playing: Bool
}

/// The menu bar's Now Playing item (macOS 26 on), found by hit-testing along
/// the menu bar: the menu bar's own list doesn't name it.
func nowPlayingMenuItem() -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    // The primary display's: hit-test coordinates start at its top left, and
    // NSScreen.main is the one with the keyboard focus, maybe another.
    let width = Float(NSScreen.screens.first?.frame.width ?? 1470)
    var x = width - 20
    while x > width / 3 {
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(system, x, 12, &hit) == .success, let hit,
           hit.text(kAXIdentifierAttribute) == "com.apple.menuextra.now-playing" { return hit }
        x -= 6
    }
    return nil
}

/// The open panel's rows, from Control Center's windows; none while it's closed.
func panelRows() -> [PanelRow] {
    guard let center = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { return [] }
    var found: [PanelRow] = []
    func walk(_ element: AXUIElement, _ depth: Int) {
        guard depth < 20 else { return }
        let children = element.children
        if let button = children.first(where: { ["play.fill", "pause.fill"].contains($0.text(kAXIdentifierAttribute)) }) {
            let text = children.map { $0.text(kAXValueAttribute) }.filter { !$0.isEmpty }.joined(separator: " ")
            found.append(PanelRow(text: text, button: button, playing: button.text(kAXIdentifierAttribute) == "pause.fill"))
            return
        }
        children.forEach { walk($0, depth + 1) }
    }
    for window in AXUIElementCreateApplication(center.processIdentifier).value(kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        walk(window, 0)
    }
    return found
}

/// A text in lowercase, its letters and digits only, one space between
/// words: so "Song (Edit) - Artist" and "song edit artist" compare.
func normalized(_ text: String) -> String {
    text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
}

/// What a row's song can be: its text up to each ", " ahead of " – <album>",
/// since the song and the artist may both hold commas ("…(JAKE DILE
/// REWORK), Jake Dile - Mixes, Bootlegs, Mashups – "); the whole text
/// without one ("QuickTime Player"). A session with no song shows its app's
/// name ("TIDAL,  – ").
func songs(ofRow text: String) -> [String] {
    let end = text.range(of: " –", options: .backwards)?.lowerBound ?? text.endIndex
    var songs: [String] = [], from = text.startIndex
    while let comma = text.range(of: ", ", range: from..<end) {
        songs.append(String(text[..<comma.lowerBound]))
        from = comma.upperBound
    }
    return songs.isEmpty ? [text] : songs
}

/// The texts of the page's player bar (the song and the artist, where
/// SoundCloud's window keeps a generic title); none without a page or a bar.
func playerBarTexts(_ pid: pid_t) -> [String] {
    guard page?.toggle != nil, pageToggleLabel(pid) != nil, let toggle = barToggle, let bar = playerBar(of: toggle) else { return [] }
    var texts: [String] = [], reads = 500
    func read(_ element: AXUIElement, depth: Int) {
        guard reads > 0 else { return }
        reads -= 1
        texts += [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].map { element.text($0) }.filter { !$0.isEmpty }
        if depth < 8 { element.children.forEach { read($0, depth: depth + 1) } }
    }
    read(bar, depth: 0)
    return texts
}

/// The rows that show what the app plays: their song found whole in
/// `texts` (its windows' titles, its player bar, its current track), or,
/// with no song, its name. A row isn't taken for a word in common: a paused
/// Deezer's "Another One Bites The Dust" was pressed for SoundCloud for its
/// "the".
func appRows(_ rows: [PanelRow], texts: [String]) -> [PanelRow] {
    let own = normalized(appName)
    // A session with no song shows its app's name: another app's.
    let others = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName.map(normalized) }).subtracting([own])
    let haystack = texts.map { " \(normalized($0)) " }
    return rows.filter { row in
        songs(ofRow: row.text).map(normalized).contains { shown in
            if shown == own { return true }
            guard shown.count >= 3, !others.contains(shown) else { return false }
            return haystack.contains { $0.contains(" \(shown) ") }
        }
    }
}

/// The row pressed last, to find it again; why the panel couldn't be used.
var panelRowText: String?
var panelProblem: String?

/// Which row to press: the app's; the one pressed last, else the app's; or
/// only the one pressed last (to put back a press that changed it).
enum PanelRowChoice { case app, lastElseApp, lastOnly }

/// Opens the panel, presses the Play/Pause of a row (the row shows Pause
/// when `pausing`, Play otherwise) and closes it; true once pressed. The
/// rows don't name their apps (only an icon shows it), so the app's row is
/// the one showing its song (`appRows`: by its windows' titles, its page's
/// player bar or its AppleScript current track); while pausing, else the
/// only row playing when the app is the Now Playing one. Nothing is pressed
/// when that's not one row. The panel shows under the menu bar for about
/// half a second, and takes the keyboard meanwhile.
func pressInPanel(pid: pid_t, pausing: Bool, choice: PanelRowChoice = .app) -> Bool {
    // Read before the panel opens: a page takes a moment.
    var texts: [String] = []
    if choice != .lastOnly {
        texts = appWindows(of: pid).windows.map(\.title)
        texts += playerBarTexts(pid)
        if let song = scriptedSong() { texts.append(song) }
    }
    let holdsNowPlaying = choice != .lastOnly && pausing && nowPlayingHolder(pid).isThisApp
    guard let item = nowPlayingMenuItem() else {
        panelProblem = "no Now Playing item in the menu bar (it shows once something has played, unless System Settings → Control Center hides it)"
        return false
    }
    guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
        panelProblem = "the Now Playing item didn't open"
        return false
    }
    var rows: [PanelRow] = []
    let deadline = Date().addingTimeInterval(2)
    while rows.isEmpty, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
        rows = panelRows()
    }
    func close() {
        _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
        let deadline = Date().addingTimeInterval(2)
        while !panelRows().isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    }
    let candidates = rows.filter { $0.playing == pausing }
    var row = choice == .app ? nil : candidates.first { $0.text == panelRowText }
    var mine: [PanelRow] = []
    if row == nil, choice != .lastOnly {
        mine = appRows(candidates, texts: texts)
        row = mine.count == 1 ? mine[0] : mine.isEmpty && holdsNowPlaying && candidates.count == 1 ? candidates[0] : nil
    }
    guard let row else {
        let state = pausing ? "Pause" : "Play"
        panelProblem = rows.isEmpty ? "the panel showed no rows"
            : choice == .lastOnly ? "the row pressed before ('\(panelRowText ?? "")') no longer shows \(state)"
            : mine.count > 1 ? "\(mine.count) of the panel's rows with \(state) show \(appName)'s song: which is its own can't be told"
            : "none of the panel's \(candidates.count) rows with \(state) shows \(appName)'s song (read from "
                + (["its windows' titles"] + (page?.toggle != nil ? ["its player bar"] : [])
                    + (scripting?.hasCurrentTrack == true ? ["its current track by AppleScript"] : [])).joined(separator: " or ")
                + ") or its name; the rows don't name their apps"
        close()
        return false
    }
    panelRowText = row.text
    let pressed = AXUIElementPerformAction(row.button, kAXPressAction as CFString) == .success
    close()
    return pressed
}

/// How a press by the panel went (`--via panel`).
enum PanelPress { case already, changed, pressed, notPressed }

/// A press by the panel (`--via panel`). The app's row is found by its song
/// in its windows' titles or its current track (Deezer's title and
/// Spotify's track name it); only when none matches is its page read, for
/// its player bar's song (SoundCloud's title doesn't name it), since reading
/// a page can take seconds (Deezer's is built anew each time). The row's own
/// Play/Pause, as Now Playing knows the app, tells whether it's that way
/// already, and shows the press take before the panel closes (2 s at most).
/// A row told only by the app holding Now Playing (pausing, the only row
/// playing) is pressed, but `.pressed`: whether it was the app's is judged
/// by the app itself.
func panelPress(pid: pid_t, pausing: Bool) -> PanelPress {
    // Its one line comes after: what it reads meanwhile isn't said.
    let wasQuiet = quiet
    quiet = true
    defer { quiet = wasQuiet }
    // The remembered player bar, when it's there, costs a few reads.
    if !pageRead { _ = useRememberedBar(pid: pid) }
    var texts = appWindows(of: pid).windows.map(\.title) + playerBarTexts(pid)
    if let song = scriptedSong() { texts.append(song) }
    guard let item = nowPlayingMenuItem() else {
        panelProblem = "no Now Playing item in the menu bar (it shows once something has played, unless System Settings → Control Center hides it)"
        return .notPressed
    }
    func open() -> [PanelRow]? {
        guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { return nil }
        var rows: [PanelRow] = []
        let deadline = Date().addingTimeInterval(2)
        while rows.isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            rows = panelRows()
        }
        return rows
    }
    func close() {
        _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
        let deadline = Date().addingTimeInterval(2)
        while !panelRows().isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    }
    guard var rows = open() else {
        panelProblem = "the Now Playing item didn't open"
        return .notPressed
    }
    var mine = appRows(rows, texts: texts)
    if mine.isEmpty, !pageRead, isWebApp || hiddenInterface != nil || hasWebPage(pid: pid) {
        close()
        readPage()
        texts += playerBarTexts(pid)
        guard let again = open() else {
            panelProblem = "the Now Playing item didn't open"
            return .notPressed
        }
        rows = again
        mine = appRows(rows, texts: texts)
    }
    if mine.count == 1 {
        let row = mine[0]
        panelRowText = row.text
        if row.playing != pausing {
            close()
            return .already
        }
        guard AXUIElementPerformAction(row.button, kAXPressAction as CFString) == .success else {
            close()
            panelProblem = "its row's \(pausing ? "Pause" : "Play") didn't take the press"
            return .notPressed
        }
        let deadline = Date().addingTimeInterval(2)
        var changed = false
        while !changed, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            changed = panelRows().first { $0.text == row.text }?.playing == !pausing
        }
        close()
        return changed ? .changed : .pressed
    }
    let candidates = rows.filter { $0.playing == pausing }
    if mine.isEmpty, pausing, candidates.count == 1, nowPlayingHolder(pid).isThisApp {
        panelRowText = candidates[0].text
        let pressed = AXUIElementPerformAction(candidates[0].button, kAXPressAction as CFString) == .success
        close()
        return pressed ? .pressed : .notPressed
    }
    close()
    panelProblem = rows.isEmpty ? "the panel showed no rows"
        : mine.count > 1 ? "\(mine.count) of the panel's rows show \(appName)'s song: which is its own can't be told"
        : "none of the panel's \(rows.count) rows shows \(appName)'s song (read from "
            + (["its windows' titles"] + (page?.toggle != nil ? ["its player bar"] : [])
                + (scripting?.hasCurrentTrack == true ? ["its current track by AppleScript"] : [])).joined(separator: " or ")
            + ") or its name; the rows don't name their apps"
    return .notPressed
}

// MARK: The test

var scriptResult: TrialResult?
var menuResult: TrialResult?
var pageResult: TrialResult?
var panelResult: TrialResult?
/// Why a way wasn't tried, for "Ways to control it".
var notTried = readOnly ? "not tried: read only" : "not tried"
var notifications: NotificationLog?
if testing {
    say()
    say("Press test")
    let script = scriptControls()
    if running == nil {
        say("  not run: the app isn't running")
    } else if script == nil, menu == nil, page?.toggle == nil, !canBeNowPlaying {
        // Nothing to press, and nothing for the panel to reach:
        // asking for it to play would only wait.
        say("  not run: nothing to press (no AppleScript play or pause, playback menu or page button), and \(notNowPlaying)")
        notTried = "not tried: nothing to press"
    } else if let running {
        let pid = running.processIdentifier
        notifications = NotificationLog(bundleID: bundleID)
        // Each way needs it playing: whoever runs the tool is asked to start
        // it before the first, and whenever a way leaves it stopped.
        var going = true
        func ready() -> Bool {
            guard going else { return false }
            going = waitUntilPlaying(pid)
            if !going {
                notTried = "not tried: it didn't play"
                say("  stopped: \(appName) didn't play within 2 minutes")
            } else {
                // Its page while it plays, to learn its Play/Pause from the first pause.
                noteLearningPlaying(pid: pid)
            }
            return going
        }
        if let script, scriptProblem == nil, ready() {
            // A toggle is sent for the pause only while it plays, and again to play.
            scriptResult = trial("by script (\(script.pause), \(script.play))", pid: pid,
                                 pause: { sendScript(script.pause) }, play: { sendScript(script.play) },
                                 whilePaused: { checkVolume(); learnPageButton(pid: pid) })
            stopIfRequested()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
        if menu != nil, ready() {
            menuResult = trial("by its menu", pid: pid, pause: { pressMenuToggle(pid: pid) }, play: { pressMenuToggle(pid: pid) },
                               whilePaused: { learnPageButton(pid: pid) })
            stopIfRequested()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
        // No other way paused it and no button is named Play or Pause: as
        // AutoHush asks ("It's Paused"), whoever runs the check pauses it, and
        // the button whose words changed is learned (the user's choice, 2026-10-12).
        let pausedByAnother = [scriptResult, menuResult].contains { $0 == .worked || $0 == .pausedOnly }
        if learned == nil, !pausedByAnother, page?.toggle == nil, page?.buttons ?? 0 > 0, ready() {
            say("  waiting: pause \(appName) yourself (its own Pause, anywhere): the check learns its page's Play/Pause from what"
                + " changes on it (up to 2 minutes)")
            let deadline = Date().addingTimeInterval(120)
            while isPlaying(pid), Date() < deadline, !stopState.isRequested { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }
            if !isPlaying(pid) {
                say("  it paused: learning")
                learnPageButton(pid: pid)
            } else {
                say("  it didn't pause within 2 minutes: its page's Play/Pause isn't learned")
            }
            stopIfRequested()
        }
        if page?.toggle != nil, ready() {
            func pressPage(pausing: Bool) -> Bool {
                guard let button = pageButtonToPress(pid: pid, pausing: pausing) else {
                    say("    no button in sight to press"); return false
                }
                var why: String?
                guard pressPageButton(button, pausing: pausing, why: &why) else {
                    if let why { say("    \(why)") }
                    return false
                }
                return true
            }
            pageResult = trial("by its page's " + (learned == nil ? "button" : "learned button"), pid: pid,
                               pause: { pressPage(pausing: true) }, play: { pressPage(pausing: false) },
                               whilePaused: { learnPageButton(pid: pid) })
            if pageResult == .didNotPause, learned != nil || page?.toggle != nil {
                say("    a pause its page refuses: AutoHush would mute it instead")
            }
            stopIfRequested()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
        if !canBeNowPlaying {
            panelProblem = panelNotNowPlaying
            say("  the Now Playing panel: not pressed: \(notNowPlaying)")
            panelResult = .didNotPause
        } else {
            if ready() {
                panelResult = trial("by the Now Playing panel", pid: pid, pause: { pressInPanel(pid: pid, pausing: true) },
                                    play: { pressInPanel(pid: pid, pausing: false, choice: .lastElseApp) },
                                    undo: {
                                        // The row pressed may have been another app's: pressed again, that app plays on.
                                        if panelRowText != nil { _ = pressInPanel(pid: pid, pausing: false, choice: .lastOnly) }
                                    },
                                    whilePaused: { learnPageButton(pid: pid) })
                if let panelProblem { say("    \(panelProblem)") }
                stopIfRequested()
            }
        }
        if let seen = notifications?.seen, !seen.isEmpty {
            for (name, keys) in seen.sorted(by: { $0.key < $1.key }) {
                say("  notification: \(name)" + (keys.isEmpty ? "" : " [\(keys.sorted().joined(separator: ", "))]"))
            }
        } else {
            say("  notifications: none under the usual names (\(bundleID).\(stateNotificationSuffixes[0]), …)")
        }
    }
}

// MARK: - Play or pause (--play, --pause)

/// Turns back off the switches this tool turned on, then exits.
func finish(_ code: Int32) -> Never {
    switchesBackOff()
    exit(code)
}

if let action {
    quiet = false
    guard let running else {
        say("\(appName) isn't running: open it first.")
        finish(1)
    }
    let pid = running.processIdentifier
    let pausing = action == "pause"
    /// Waits up to 6 s for `done`, looking every 0.05 s.
    func within(_ done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(6)
        while !done() {
            guard Date() < deadline else { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return true
    }
    var tried: [String] = []
    for way in via.map({ [$0] }) ?? ["script", "page", "menu"] {
        switch way {
        case "script":
            guard let script = scriptControls() else {
                tried.append("no AppleScript play or pause")
                continue
            }
            // Its state answers when it has one (Spotify's, VLC's playing flag); else what shows.
            let isThere = { isPlaying(pid) != pausing }
            if isThere() {
                say("It's \(pausing ? "paused" : "playing") already.")
                finish(0)
            }
            let command = pausing ? script.pause : script.play
            // Its state notification, as AutoHush follows it, confirms as
            // soon as it comes; else its asked state does.
            let announced = NotificationLog(bundleID: bundleID)
            let sentAt = Date()
            let byNotification = { announced.lastState(since: sentAt).map { pausing ? $0 != .playing : $0 == .playing } == true }
            guard sendScript(command) else {
                tried.append(scriptProblem ?? "AppleScript \(command) failed")
                continue
            }
            if within({ byNotification() || isThere() }) {
                say("\(pausing ? "Paused" : "Played") it by AppleScript (\(command))"
                    + (byNotification() ? ", as its notification announced." : "."))
                finish(0)
            }
            tried.append("AppleScript \(command) sent, but it didn't change in 6 s")
        case "page":
            guard page?.toggle != nil else {
                tried.append((pageOutOfView ? "its page didn't show with "
                    + (hiddenInterface?.switches.map(switchName).joined(separator: " or ") ?? "the switch") + " on" : "no Play/Pause button on its page")
                    + (pageOutOfView ? pagePressHint() : ""))
                continue
            }
            // As it reports to Now Playing, else as its page's button says
            // (Pause while it plays, Play while it doesn't).
            let done = { isPlaying(pid) != pausing }
            if done() {
                say("It's \(pausing ? "paused" : "playing") already.")
                finish(0)
            }
            guard let button = pageButtonToPress(pid: pid, pausing: pausing) else {
                tried.append("couldn't find its page's \(pausing ? "Pause" : "Play")")
                continue
            }
            var why: String?
            guard pressPageButton(button, pausing: pausing, why: &why) else {
                tried.append(why ?? "couldn't press its page's \(pausing ? "Pause" : "Play")")
                continue
            }
            if within(done) {
                learnFromPress(button.element, before: button.label, pausing: pausing)
                say("\(pausing ? "Paused" : "Played") it with its page's '\(button.label)' button"
                    + (pageSwitch.map { ", \(switchName($0)) on" } ?? "")
                    + (broughtForward ? " (brought forward a moment: Chromium and Flutter apps may build it only while their window can be seen)." : "."))
                finish(0)
            }
            tried.append("pressed its page's '\(button.label)', but it didn't change in 6 s"
                + (pausing ? " (AutoHush would mute it instead)" : "")
                + (hiddenInterface != nil && !button.onScreen ? pagePressHint() : ""))
        case "menu":
            guard let menu else {
                tried.append("no playback menu")
                continue
            }
            // Its first item toggles, so it's pressed only when it's the
            // other way; judged as a test judges it (`Sign`): its menu's word
            // counts only for an app with no surer sign, as Deezer's changes
            // late by itself.
            let before = lookForSign(pid)
            let sign = Sign(before: before)
            let done = { (now: Look) in pausing ? sign.paused(now) : sign.playing(now) }
            if done(before) {
                say("It's \(pausing ? "paused" : "playing") already.")
                finish(0)
            }
            let word = before.menuTitle ?? ""
            guard pressMenuToggle(pid: pid) else {
                tried.append("couldn't press its menu's first item")
                continue
            }
            if within({ done(look(pid, level: sign.byLevel)) }) {
                say("\(pausing ? "Paused" : "Played") it with its '\(menu.title)' menu's '\(word)'.")
                finish(0)
            }
            tried.append("pressed its menu's '\(word)', but nothing changed in 6 s")
        case "panel":
            // Its row says whether it's that way already, and shows the press take.
            switch panelPress(pid: pid, pausing: pausing) {
            case .already:
                say("It's \(pausing ? "paused" : "playing") already.")
                finish(0)
            case .changed:
                say("\(pausing ? "Paused" : "Played") it with its row in the Now Playing panel ('\(panelRowText ?? "")').")
                finish(0)
            case .notPressed:
                tried.append(panelProblem ?? "couldn't press its row in the Now Playing panel")
                continue
            case .pressed:
                break
            }
            if within({ isPlaying(pid) != pausing }) {
                say("\(pausing ? "Paused" : "Played") it with its row in the Now Playing panel ('\(panelRowText ?? "")').")
                finish(0)
            }
            // That row changed and this app didn't: another app's after all, put back as it was.
            let pressedRow = panelRowText ?? ""
            let putBack = pressInPanel(pid: pid, pausing: !pausing, choice: .lastOnly)
            tried.append("pressed a row in the Now Playing panel ('\(pressedRow)'), but it didn't change in 6 s"
                + (putBack ? "; that row had changed, so it was pressed again to put it back" : ""))
        default:
            tried.append("no way called '\(way)' (script, menu, page or panel)")
        }
    }
    say("Couldn't \(action) it: " + tried.joined(separator: "; ") + ".")
    finish(1)
}

// MARK: - Ways to control it

/// One line per way known to control an app, each with a mark: ✓ it paused
/// and played again in the test, ✗ not there or didn't work, ? found but not
/// tried (read only, or it didn't play), – not checked. The Player Check app
/// shows this section as a checklist.
func way(_ mark: String, _ text: String) { say("  \(mark) \(text)") }
say()
say("Ways to control it")
if let script = scriptControls() {
    let fits = scripting?.fitsScriptablePlayer == true
    let kind = fits ? ", as Spotify and Apple Music"
        : " (\(scripting?.playsDocuments == true ? "on its documents, " : "")its own kind, as VLC: not the way ScriptablePlayers expects)"
    switch scriptResult {
    case .worked?: way("✓", "AppleScript: '\(script.pause)' and '\(script.play)' paused and played it\(kind)")
    case .pausedOnly?: way("✗", "AppleScript: '\(script.pause)' paused it, but '\(script.play)' didn't play it again")
    case .didNotPause?: way("✗", "AppleScript: " + (scriptProblem ?? "'\(script.pause)' didn't pause it"))
    case nil:
        if let scriptProblem {
            way("✗", "AppleScript: \(scriptProblem)")
        } else if fits {
            way("?", "AppleScript: pause, play and its state, as Spotify and Apple Music (\(notTried))")
        } else {
            way("?", "AppleScript: play or pause commands, but not as Spotify's (a player type of its own, as VLC) (\(notTried))")
        }
    }
} else {
    way("✗", "AppleScript: " + (scripting == nil ? "no scripting dictionary" : "a dictionary without play or pause"))
}
/// A trial's line: ✓ paused and played again, ✗ it only paused or didn't.
func resultLine(_ title: String, _ result: TrialResult, problem: String? = nil) {
    switch result {
    case .worked: way("✓", "\(title): pressing it paused and played it")
    case .pausedOnly: way("✗", "\(title): " + (problem ?? "it paused, but didn't play again"))
    case .didNotPause: way("✗", "\(title): " + (problem ?? "pressing it changed nothing"))
    }
}
if running == nil {
    way("–", "Playback menu: not checked (it isn't running)")
} else if !AXIsProcessTrusted() {
    way("–", "Playback menu: not checked (no Accessibility permission)")
} else if let menu {
    let found = "Playback menu '\(menu.title)'" + (menu.asAutoHushFindsIt ? "" : " (found by \(menu.arrows), not ⌘← ⌘→)")
    if let menuResult {
        resultLine(found, menuResult)
    } else {
        way("?", "\(found): first item '\(menu.toggleTitle)' (\(notTried))")
    }
} else {
    way("✗", "Playback menu: none with Play/Pause and Previous/Next")
}
if let pageNotChecked {
    way("–", "Page button: not checked (\(pageNotChecked))")
} else if let page {
    let kind = pageSwitch.map { "Page button, with \(switchName($0)) on" } ?? "Page button"
    if let toggle = page.toggle {
        let found = "\(kind): " + (learned.map { "'\($0.recipe.pauseLabel)' / '\($0.recipe.playLabel)', learned as AutoHush learns it" }
                                   ?? "'\(toggle.label)'" + (page.withControls ? "" : ", but no player bar around it"))
        if let pageResult {
            resultLine(found, pageResult)
        } else {
            way("?", "\(found) (\(notTried))")
        }
    } else {
        way("✗", "\(kind): " + (page.buttons == 0 ? "no page showed" : "none in sight named Play or Pause"))
    }
}
if let panelResult {
    if panelResult == .worked {
        way("✓", "Now Playing panel: pressing its row ('\(panelRowText ?? "")') paused and played it")
    } else {
        resultLine("Now Playing panel", panelResult, problem: panelProblem)
    }
} else if running == nil {
    way("–", "Now Playing panel: not checked (it isn't running)")
} else if !canBeNowPlaying {
    way("✗", "Now Playing panel: \(panelNotNowPlaying)")
} else {
    way("?", "Now Playing panel: its rows in the menu bar's panel play and pause the apps listed there (\(notTried))")
}

// MARK: - Verdict

say()
say("Verdict")
if isWebApp {
    say("  A Safari web app: AutoHush learns its page's Play/Pause button (WebAppPlayers).")
    say("  Test the site live, then add it to SupportedPlayers.testedWebApps.")
} else if let scripting, scripting.fitsScriptablePlayer, let suite = scripting.suite {
    say("  Scriptable, like Spotify and Apple Music: a ScriptablePlayerProfile with suite fourCharCode(\"\(suite)\").")
    say("  " + (scripting.hasVolume ? "It has a volume: measure its curve (swift run measure-volume-curve \(bundleID))."
                                     : "No volume: it pauses without fading."))
    let stateNotes = notifications?.seen.filter { $0.value.contains("Player State") }.keys.sorted() ?? []
    if let announcingNotification {
        say("  State notification: \(announcingNotification), which announced each pause and play (the profile's stateNotification).")
    } else if !stateNotes.isEmpty {
        say("  State notification: \(stateNotes.joined(separator: ", ")), but it didn't announce both a pause and a play in the test.")
    } else if notifications == nil {
        say("  Its state notification (with \"Player State\") isn't known yet: check it again while it plays.")
    } else {
        say("  No state notification with \"Player State\" under the usual names: unless it has one under another,")
        say("  its state must be read once a second (PolledStateObserver), so the profile needs that option.")
    }
    switch scriptResult {
    case .didNotPause?: say("  But its scripted pause didn't take: check it by hand before building on it.")
    case .pausedOnly?: say("  But its scripted play didn't bring it back: check it by hand before building on it.")
    default: break
    }
} else if menu != nil {
    switch menuResult {
    case .worked?:
        say("  A menu player, like TIDAL and Apple Podcasts: a MenuPlayerProfile with menu '\(menu!.title)'.")
        say("  Its words for Play and Pause in every language must be read from the app (TidalWords, PodcastsWords).")
        if !menu!.asAutoHushFindsIt { say("  And AutoHush must find the menu by \(menu!.arrows) as well as ⌘← ⌘→.") }
    case .pausedOnly?:
        say("  Its menu paused it, but pressing it again didn't play it: check it by hand before building on it.")
    case .didNotPause?:
        say("  Its menu has Play/Pause, but pressing it didn't take (as Deezer's menu): not controllable that way.")
    case nil:
        say("  Probably a menu player, like TIDAL and Apple Podcasts (menu '\(menu!.title)'): confirm by testing it while it plays.")
        if !menu!.asAutoHushFindsIt { say("  AutoHush would also have to find the menu by \(menu!.arrows), not only ⌘← ⌘→.") }
    }
    if let scripting, scripting.commands.values.contains(where: { ["play", "pause", "playpause"].contains($0.lowercased()) }) {
        say("  It's scriptable too, but not the way ScriptablePlayers expects (see above): maybe a player type of its own, as VLC.")
    }
} else if let scripting, scripting.commands.values.contains(where: { ["play", "pause", "playpause"].contains($0.lowercased()) }) {
    say("  Scriptable" + (scripting.playsDocuments ? " through its documents (its play and pause act on one)" : "")
        + ", but not the way ScriptablePlayers expects: a player type of its own, as VLC (VLCSupport).")
} else if running == nil {
    say("  No usable scripting; open it and run again to look for a playback menu and a page.")
} else if page?.toggle != nil {
    say("  Neither scriptable nor with a playback menu.")
} else {
    say("  Neither scriptable nor with a playback menu: AutoHush can't control it. If it has a website, try that as a Safari web app.")
}

// What the page showed. AutoHush has no player kind for apps' pages yet: a
// player that learns the page's button, as WebAppPlayers does for Safari
// web apps, would be one.
if let page {
    let pageWord = isFlutter ? "interface" : "page"
    let its = pageSwitch.map { "With \(switchName($0)) on, its \(pageWord)" } ?? "Its \(pageWord)"
    if page.buttons == 0 {
        say(hiddenInterface != nil ? "  No switch showed its \(pageWord): its buttons can't be read that way."
                                   : "  Its page showed no buttons: is the site loaded?")
    } else if let toggle = page.toggle {
        switch pageResult {
        case .worked?:
            if isWebApp {
                say("  Its page's Play/Pause works.")
            } else {
                say("  \(its)'s Play/Pause works: it could be a player that learns that button,")
                say("  as Safari web apps (WebAppPlayers), with no fades; AutoHush has no such player for apps yet.")
            }
        case .pausedOnly?:
            say("  \(its)'s Pause works, but its Play didn't bring it back: check by ear.")
        case .didNotPause?:
            say("  \(its) has Play/Pause ('\(toggle.label)'), but pressing it didn't take: check by ear.")
        case nil:
            say("  \(its) has Play/Pause ('\(toggle.label)'): confirm by testing it while it plays.")
        }
        if !page.withControls {
            say("  But no player's slider is around it: likely a song's own button, not a player bar (is a song loaded,")
            say("  is someone signed in?). Run it again with a song playing.")
        }
    } else {
        say("  \(its) shows \(page.buttons) \(isFlutter ? "pressable items" : "buttons"), but none in sight is named Play or Pause:")
        say("  see them with Accessibility Inspector (in Xcode: Open Developer Tool; its language may not be one this tool")
        say("  knows, its player may be hidden, or its buttons may have no names, as Spotube's player bar).")
    }
}

let turnedOn = stopState.switchesOn
if !turnedOn.isEmpty {
    let stuck = switchesBackOff()
    say()
    for attribute in turnedOn {
        say(stuck.contains(attribute) ? "(Couldn't set \(switchName(attribute)) back to off.)"
                                      : "(\(switchName(attribute)) set back to off, as it was.)")
    }
}
