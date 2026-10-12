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
//                                                      started first when it isn't playing), with its window
//                                                      in each state a player's can be in (visible, covered,
//                                                      on another desktop, covered there, full screen,
//                                                      minimised, hidden), then puts its window back
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
//   playercheck --launch-option <app>                  the launch option it needs (Electron's apps), and whether it
//                                                      runs with it: "<option or nothing>\t<yes|no|not running>"
//   playercheck --relaunch <app>                       quits it, then opens it again with that option, in the background
//   playercheck --window-state <app>                   the state its main window is in now (visible, covered, …)
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

/// --launch-option, --relaunch and --window-state <app>, for the Player
/// Check app: whether the app needs a launch option and runs with it
/// ("<option, or nothing>\t<yes|no|not running>"), quitting it and opening
/// it again with that option, and the state its window is in now (one of
/// `WindowState`'s titles, "no window" or "not running"), for its Play and
/// Pause by the way that worked in that state.
if let option = CommandLine.arguments.dropFirst().first, ["--launch-option", "--relaunch", "--window-state"].contains(option) {
    guard CommandLine.arguments.count > 2, let url = findApp(CommandLine.arguments[2]), let id = Bundle(url: url)?.bundleIdentifier else {
        print("no app found")
        exit(1)
    }
    let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first
    switch option {
    case "--launch-option":
        let needed = LaunchOption.needed(by: url)
        print([needed ?? "", needed == nil ? "" : app.map { LaunchOption.arguments(of: $0.processIdentifier).contains(needed!) ? "yes" : "no" }
                                                ?? "not running"].joined(separator: "\t"))
        exit(0)
    case "--relaunch":
        guard let needed = LaunchOption.needed(by: url) else {
            print("It needs no launch option.")
            exit(1)
        }
        exit(LaunchOption.relaunch(app, url: url, with: needed) ? 0 : 1)
    default:
        print(app.map { WindowStates.state(of: $0)?.title ?? "no window" } ?? "not running")
        exit(0)
    }
}

// MARK: - The app

let arguments = Array(CommandLine.arguments.dropFirst())
// The app is the argument that's neither an option nor --via's way, wherever it comes.
guard let target = arguments.indices.first(where: { !arguments[$0].hasPrefix("--") && ($0 == 0 || arguments[$0 - 1] != "--via") })
    .map({ arguments[$0] }) else {
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
    /// Else a property of its own naming it (VLC's `name of current item`,
    /// AANA): its panel row shows that name too, wherever its window is.
    var currentItemName: String? { properties.first { $0.value == "name of current item" }?.key }
    /// Whether it says by script what it plays (`scriptedSong`).
    var namesItsSong: Bool { hasCurrentTrack || currentItemName != nil }
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
        // TIDAL has ⌘← for Previous and ⇧⌘← for Seek back. An item that doesn't
        // say counts as ⌘ here, but AutoHush takes only one that says 0.
        var arrows: [Int: [Int]] = [:], saidCommand: Set<Int> = []
        for item in menu.children {
            if let key = item.value(kAXMenuItemCmdVirtualKeyAttribute) as? Int, key == 123 || key == 124 {
                let modifiers = item.value(kAXMenuItemCmdModifiersAttribute) as? Int
                arrows[key, default: []].append(modifiers ?? 0)
                if modifiers == 0 { saidCommand.insert(key) }
            }
        }
        guard let left = arrows[123], let right = arrows[124] else { continue }
        if left.contains(0), right.contains(0) {
            let asAutoHush = saidCommand == [123, 124]
            return FoundMenu(title: barItem.title, toggle: first, asAutoHushFindsIt: asAutoHush,
                             arrows: asAutoHush ? "⌘← ⌘→" : "← → (with no modifiers given)")
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
    // Whole or not at all: a run stopped mid-write (`_exit`) leaves the old file.
    try? JSONEncoder().encode(cache).write(to: cacheFile, options: .atomic)
    return found.map { (PlayPauseWords(play: Set($0.play), pause: Set($0.pause)), $0.source) }
}

/// Whether anything in it can report to Now Playing (so it may have a row
/// in the Now Playing panel, and report its state), read once: it reads the
/// load commands of every binary in the app (`nowPlayingReason`).
let canBeNowPlaying = nowPlayingReason(of: appURL, bundleID: bundleID) != nil

/// Whether this account can read what apps report to Now Playing: macOS's
/// log opens only to administrators (the admin group).
let isAdministrator: Bool = {
    var groups = [gid_t](repeating: 0, count: 256)
    let count = getgroups(Int32(groups.count), &groups)
    // Unknown: taken as one, and opening the log tells.
    return count < 0 || groups.prefix(Int(count)).contains(80)
}()

/// Whether something surer than its menu's or page's word shows whether it
/// plays: its scripted state, or what it reports to Now Playing, which only
/// an administrator can read.
let hasSurerSign = scripting?.hasState == true || (canBeNowPlaying && isAdministrator)
/// A press by one way reads the menu and the page for their own way (the
/// panel needs the page's player bar, which names the song), or when nothing
/// surer shows whether the app plays.
func pressNeeds(_ ways: Set<String>) -> Bool { !pressingOneWay || ways.contains(via!) || !hasSurerSign }

/// The app's own words, for its menu's state and its page's buttons, merged
/// with this tool's list (`playWords`, `pauseWords`). A press reads them
/// whenever it may read the menu or the page (the panel's way reads the
/// page's player bar; kept, they cost a file read).
let ownAppWords = pressNeeds(["menu", "page", "panel"]) ? appWords(of: appURL) : nil
let ownWords = ownAppWords?.words

say()
say("Playback menu")
var menu: FoundMenu?
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
var isElectron: Bool { if case .electron? = hiddenInterface { true } else { false } }

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

var page: PageCheck?
/// For an Electron app that runs: whether it was opened with the option its
/// page needs to take presses out of view (`LaunchOption`).
var launchedWithOption: Bool? {
    guard isElectron, let running else { return nil }
    return LaunchOption.arguments(of: running.processIdentifier).contains(LaunchOption.occludedWindows)
}
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
    private var setOn: [String: Date] = [:]
    /// When this tool last turned `attribute` on (`waitForFullerMode`).
    func switchSetOn(_ attribute: String) { lock.withLock { setOn[attribute] = Date() } }
    func switchSetOnAt(_ attribute: String) -> Date? { lock.withLock { setOn[attribute] } }
    private var stream: pid_t = 0
    /// The `log stream` this tool follows Now Playing with, ended with it.
    var streamPID: pid_t {
        get { lock.withLock { stream } }
        set { lock.withLock { stream = newValue } }
    }
    private var windowBack: (() -> Void)?
    /// Puts the app's window back as it was, once a test moved it.
    var restoreWindow: (() -> Void)? {
        get { lock.withLock { windowBack } }
        set { lock.withLock { windowBack = newValue } }
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
    if on { stopState.switchSetOn(attribute) }
    if AXUIElementSetAttributeValue(app, attribute as CFString, on ? kCFBooleanTrue : kCFBooleanFalse) == .success { return true }
    return app.value(attribute) as? Bool == on
}

/// An Electron app takes presses on its page only in its fuller
/// accessibility mode, which starts 2 s after its switch last went on
/// (Electron debounces the requests; an off sent meanwhile cancels it, and
/// keeps a fuller mode already on: electron_application.mm). A press right
/// after the switch goes on does nothing, though the page shows and the
/// press is accepted (Deezer's, kept built by another tool reading its
/// role, 2026-10-12). So before a press: at once when the switch reads back
/// on (Electron says so only in that mode), else not before those 2 s.
func waitForFullerMode(pid: pid_t) {
    guard isElectron, let since = stopState.switchSetOnAt(manualAccessibility) else { return }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    guard app.value(manualAccessibility) as? Bool != true else { return }
    let wait = 2.2 - Date().timeIntervalSince(since)
    guard wait > 0 else { return }
    log(String(format: "  waited %.1f s for Electron's fuller mode: its page takes presses only 2 s after its switch goes on", wait))
    Thread.sleep(forTimeInterval: wait)
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
    stopState.restoreWindow?()
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

/// Turns on the app's `switches` in turn, each given 4 s for its page to
/// show: whether a page showed (in `count`, after `shownAfter` s), nil when
/// the app took none. A Chromium app builds its page only while its window
/// can be seen (Deezer's, covered: none), and once built it stays readable
/// covered, hidden or on another desktop; Spotify, on another desktop when
/// its switch went on, and Spotube, behind other windows, showed nothing
/// until the switch went on again in front. So when nothing shows, a check
/// brings the app forward a moment, once (the user, 2026-10-11: "If it's
/// only once to make the check, it's okay"), turns on there again each
/// switch it took until one shows, then brings back the app that was in
/// front. A press never does (the tool should be as unintrusive as
/// possible): it says why the page can't be read, and the page way isn't used.
func showPage(with switches: [String], pid: pid_t, count: inout Int, shownAfter: inout TimeInterval?) -> Bool? {
    /// Turns a switch this tool turned on back off.
    func off(_ attribute: String) {
        if stopState.switchesOn.contains(attribute), setSwitch(attribute, false, pid: pid) {
            stopState.switchesOn.removeAll { $0 == attribute }
        }
    }
    // The switches it took, and whether this tool turned each on (VoiceOver's
    // may have been on already: left as it is).
    var taken: [(attribute: String, ours: Bool)] = []
    var shown: (attribute: String, waited: (count: Int, after: TimeInterval))?
    for attribute in switches where shown == nil {
        guard turnOn(attribute, pid: pid, pageReadable: false) else { continue }
        taken.append((attribute, stopState.switchesOn.contains(attribute)))
        let waited = waitForPage(pid, seconds: 4)
        if waited.count > 0 {
            shown = (attribute, waited)
        } else {
            say("  \(switchName(attribute)) (\(attribute)) on, but nothing showed in 4 s")
            off(attribute)
        }
    }
    guard !taken.isEmpty else { return nil }
    if shown == nil, action != nil { pageOutOfView = true }
    if shown == nil, action == nil {
        shown = inFront(pid: pid) {
            for (attribute, ours) in taken {
                if ours, !stopState.switchesOn.contains(attribute), setSwitch(attribute, true, pid: pid) {
                    stopState.switchesOn.append(attribute)
                }
                let waited = waitForPage(pid, seconds: 6)
                if waited.count > 0 { return (attribute, waited) }
                off(attribute)
            }
            return nil
        }
        say("  its window was out of sight: brought it forward a moment, with "
            + (taken.count == 1 ? "the switch" : "each switch") + " turned on again there"
            + " (Chromium and Flutter apps may build their \(isFlutter ? "interface" : "page") only while their window can be seen)"
            + (shown == nil ? "; nothing showed there either" : ""))
    }
    guard let (attribute, waited) = shown else { return false }
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
    /// The text of its row in the Now Playing panel, once a press of it
    /// changed the app (`rememberPanelRow`).
    var panelRow: String?
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
    // Whole or not at all: a run stopped mid-write (`_exit`) would leave a
    // cut file, read as empty, and the next save would keep only this app.
    try? JSONEncoder().encode(all).write(to: placesFile, options: .atomic)
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

/// The page's buttons as AutoHush's learning takes them, and each one found
/// by its handle: only those whose words are current (`wordsCurrent`), as a
/// Chromium page out of sight lags a state, and its words would be learned
/// the wrong way round. `outOfSight`: it has buttons, but none current.
func learningButtons(_ pid: pid_t) -> (buttons: [PageButton], found: [ButtonHandle: FoundButton], outOfSight: Bool) {
    let all = pageButtons(pid: pid) ?? []
    var found: [ButtonHandle: FoundButton] = [:]
    let buttons = all.filter(wordsCurrent).map { button -> PageButton in
        let handle = ButtonHandle(button.element)
        found[handle] = button
        return PageButton(handle: handle, label: button.label, isEnabled: button.element.value(kAXEnabledAttribute) as? Bool ?? true)
    }
    return (buttons, found, buttons.isEmpty && !all.isEmpty)
}

/// Set when a look for learning found the page out of sight.
var learningOutOfSight = false

/// Says once that the page's Play/Pause isn't learned, and why.
func sayNotLearned(_ why: String) {
    guard !learningSaid else { return }
    learningSaid = true
    say("    its page's Play/Pause not learned: \(why)")
}

/// What a page button's words say of the state: by the learned recipe (the
/// site's own words), else this tool's lists ("Pause" while it plays).
func wordSays(_ words: String) -> PlayerState? {
    if let recipe = learned?.recipe ?? savedRecipe, let state = recipe.state(of: PageButton(handle: ButtonHandle(0), label: words)) {
        return state
    }
    return named(words, pauseWords) ? .playing : named(words, playWords) ? .paused : nil
}

/// Takes the look while it plays, once a test has it playing (`ready`):
/// not while its page is out of sight (taken at the next test instead).
func noteLearningPlaying(pid: pid_t) {
    guard page?.buttons ?? 0 > 0, !learner.hasPlayed, learned == nil else { return }
    let look = learningButtons(pid)
    learningOutOfSight = look.outOfSight
    guard !look.outOfSight else { return }
    learner.notePlaying(look.buttons, at: Date())
}

let outOfSightWhy = "its window is out of sight, where a Chromium or Flutter page's words lag a state behind"

/// Once a test paused it (by any way): the button whose words changed is
/// learned (`PlayPauseLearner.recipe`: in sight, with a player's controls,
/// the barest words, the lowest), saved merged with what was learned before,
/// and pressed by the page way from then on. Said once when nothing changed.
func learnPageButton(pid: pid_t) {
    guard learned == nil else { return }
    guard learner.hasPlayed else {
        if learningOutOfSight { sayNotLearned(outOfSightWhy) }
        return
    }
    let (buttons, found, outOfSight) = learningButtons(pid)
    if outOfSight { return sayNotLearned(outOfSightWhy) }
    let placed = learner.candidates(paused: buttons).compactMap { candidate in
        webPage.place(of: candidate.handle).flatMap { place in webPage.standing(of: candidate.handle).map { (candidate, place, $0) } }
    }
    guard let (recipe, handle) = PlayPauseLearner.recipe(from: placed), let button = found[handle] else {
        return sayNotLearned("none of its buttons changed words")
    }
    let element = button.element
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
        page = PageCheck(buttons: page?.buttons ?? buttons.count,
                         toggle: FoundButton(element: element, label: label(of: element), fromBottom: recipe.places[0].distanceFromBottom,
                                             inSight: true, onScreen: button.onScreen),
                         withControls: placed.first { $0.0.handle == handle }?.2.isWithPlayerControls ?? false)
        barToggle = element
    }
}

/// After a press by the page that took: what the pressed button said before
/// and after it is learned, as AutoHush learns a button again once it went
/// missing, merged with what was learned before. Only while its words are
/// current (`wordsCurrent`): out of sight, a Chromium page's lag one state,
/// and would be saved the wrong way round ('Pause' as the word for paused),
/// replacing the right ones (`merging` keeps only the newer words).
func learnFromPress(_ button: FoundButton, before: String, pausing: Bool) {
    guard wordsCurrent(button) else { return }
    let element = button.element
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
                if let launchedWithOption {
                    say("  opened with \(LaunchOption.occludedWindows): "
                        + (launchedWithOption ? "yes, so its page takes presses while its window is covered or on another desktop"
                                              : "no: its page takes no presses while its window is covered or on another desktop"
                                                + " (the Player Check app can relaunch it with it)"))
                }
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
                tookNone = showPage(with: hidden.switches, pid: pid, count: &count, shownAfter: &shownAfter) == nil
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

// MARK: - Window states

/// The states a player's window can be in while AutoHush controls it. A test
/// puts the app's main window in each, in this order (the fewest moves), and
/// tries every way there, as each may work in some only (the user,
/// 2026-10-12: Deezer's page button worked in view, not with its window full
/// screen on another desktop).
enum WindowState: CaseIterable {
    case visible, covered, otherDesktop, otherDesktopCovered, fullScreen, minimised, hidden
    /// As the report names it: the Player Check app reads these.
    var title: String {
        switch self {
        case .visible: "visible"
        case .covered: "covered"
        case .otherDesktop: "on another desktop"
        case .otherDesktopCovered: "covered on another desktop"
        case .fullScreen: "full screen"
        case .minimised: "minimised"
        case .hidden: "hidden"
        }
    }
}

/// The launch option an Electron app needs for its page to take presses
/// while its window is covered or on another desktop. Without it, Chromium
/// treats a page whose window is fully out of view as hidden and ignores
/// presses on it; with it, Deezer's worked covered, on another desktop and
/// full screen there (2026-10-12). A CEF app (Spotify) took presses covered
/// without it, so it's Electron's only.
enum LaunchOption {
    static let occludedWindows = "--disable-backgrounding-occluded-windows"

    /// The option the app needs, by the framework in its bundle.
    static func needed(by url: URL) -> String? {
        if case .electron? = HiddenInterface.of(url) { return occludedWindows }
        return nil
    }

    /// A process's launch arguments, its own path first, as `ps` reads them
    /// (`KERN_PROCARGS2`: processes of the same user).
    static func arguments(of pid: pid_t) -> [String] {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return [] }
        let count = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        // After the count: the executable's path, NULs, then the arguments.
        var index = 4
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var found: [String] = []
        while found.count < count, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            found.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return found
    }

    /// What `openApplication` answered, from the queue it answers on.
    private final class Opened: @unchecked Sendable {
        var app: NSRunningApplication?
        var error: Error?
    }

    /// Quits the app as a person would (never by force: it's given 15 s), then
    /// opens it again with `option`, in the background: an app that comes
    /// forward by itself once its window shows (Deezer does) goes behind the
    /// app that was in front again. Says how it went.
    static func relaunch(_ app: NSRunningApplication?, url: URL, with option: String) -> Bool {
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let front = WindowStates.frontPID().flatMap { NSRunningApplication(processIdentifier: $0) }
        if let app {
            _ = app.terminate()
            let deadline = Date().addingTimeInterval(15)
            while !app.isTerminated, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
            guard app.isTerminated else {
                print("\(name) didn't quit within 15 s (it may be asking something): quit it yourself, then try again.")
                return false
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [option]
        configuration.activates = false
        let opened = Opened()
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            opened.app = app
            opened.error = error
            done.signal()
        }
        guard done.wait(timeout: .now() + 30) == .success, let new = opened.app else {
            print("Couldn't open \(name) again: \(opened.error?.localizedDescription ?? "macOS didn't answer").")
            return false
        }
        // It may come forward a few seconds after its window shows (Deezer's
        // once its page loaded): watched for 12 s, sent back each time.
        if let front, front.processIdentifier != app?.processIdentifier {
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                if WindowStates.frontPID() == new.processIdentifier {
                    Thread.sleep(forTimeInterval: 0.3)
                    WindowStates.activate(front)
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        print("\(app == nil ? "Opened" : "Relaunched") \(name) with \(option) (pid \(new.processIdentifier)).")
        return true
    }
}

/// macOS's desktops (Spaces), read through SkyLight's read-only calls, as
/// window managers read them, resolved at runtime: nil when gone. Only the
/// main display's.
enum Desktops {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static func symbol<T>(_ names: [String], _ type: T.Type) -> T? {
        for name in names {
            if let found = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) { return unsafeBitCast(found, to: type) }
        }
        return nil
    }
    private static let connection = symbol(["SLSMainConnectionID", "CGSMainConnectionID"], MainConnection.self)
    private static let displaySpaces = symbol(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], CopyDisplaySpaces.self)
    private static let spacesForWindows = symbol(["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"], CopySpacesForWindows.self)

    /// The main display's desktops in order (full screen apps' among them),
    /// and the current one.
    static func all() -> (spaces: [(id: Int, isFullScreen: Bool)], current: Int)? {
        guard let connection, let displaySpaces,
              let main = (displaySpaces(connection())?.takeRetainedValue() as? [[String: Any]])?.first else { return nil }
        func id(_ space: [String: Any]?) -> Int { (space?["ManagedSpaceID"] as? Int) ?? (space?["id64"] as? Int) ?? 0 }
        let listed = main["Spaces"] as? [[String: Any]] ?? []
        let spaces: [(id: Int, isFullScreen: Bool)] = listed.map { space in (id: id(space), isFullScreen: space["type"] as? Int == 4) }
        guard !spaces.isEmpty else { return nil }
        return (spaces, id(main["Current Space"] as? [String: Any]))
    }

    /// The desktop a window is on.
    static func of(window: Int) -> Int? {
        guard let connection, let spacesForWindows,
              let spaces = spacesForWindows(connection(), 7, [window] as CFArray)?.takeRetainedValue() as? [Int] else { return nil }
        return spaces.first
    }

    /// Where a desktop is in the main display's order.
    static func index(of id: Int) -> Int? { all()?.spaces.firstIndex { $0.id == id } }
}

/// Reading an app's main window's state, and changing it as a person would.
enum WindowStates {
    typealias Info = [String: Any]
    static func infos(_ option: CGWindowListOption) -> [Info] {
        CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [Info] ?? []
    }
    static func frame(of info: Info) -> CGRect {
        (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
    }
    static func number(of info: Info) -> Int { info[kCGWindowNumber as String] as? Int ?? 0 }

    /// The app's main window: its biggest ordinary one that Accessibility
    /// knows, wherever it is (a full screen window may come with a bigger one
    /// it doesn't: Music's), else its biggest.
    static func mainWindow(of pid: pid_t) -> Info? {
        let candidates = infos(.optionAll).filter {
            $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0 && frame(of: $0).height >= 200
        }
        func area(_ info: Info) -> CGFloat { frame(of: info).width * frame(of: info).height }
        let known = Set(windowElements(of: pid).map(\.number))
        return candidates.filter { known.contains(number(of: $0)) }.max { area($0) < area($1) } ?? candidates.max { area($0) < area($1) }
    }

    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow: GetWindow? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow")
        .map { unsafeBitCast($0, to: GetWindow.self) }

    /// The app's windows Accessibility knows, with their numbers: this
    /// desktop's (minimised ones too) and every other's (`AccessibilityWindows`).
    static func windowElements(of pid: pid_t) -> [(number: Int, element: AXUIElement)] {
        guard let getWindow else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var found: [(number: Int, element: AXUIElement)] = []
        for element in app.elements(kAXWindowsAttribute) + (AccessibilityWindows.windows(ofProcess: pid) ?? []) {
            var id: CGWindowID = 0
            if getWindow(element, &id) == .success, !found.contains(where: { $0.number == Int(id) }) { found.append((Int(id), element)) }
        }
        return found
    }

    /// A window's Accessibility element.
    static func element(of pid: pid_t, number: Int) -> AXUIElement? {
        windowElements(of: pid).first { $0.number == number }?.element
    }

    /// Whether the windows on screen above it cover every point of a grid over it.
    static func isCovered(_ info: Info) -> Bool {
        let list = infos(.optionOnScreenOnly)
        guard let index = list.firstIndex(where: { number(of: $0) == number(of: info) }) else { return false }
        let above = list[..<index].filter { other in
            other[kCGWindowLayer as String] as? Int == 0 && (other[kCGWindowAlpha as String] as? Double ?? 1) > 0
        }.map(frame(of:))
        let box = frame(of: info)
        for row in 0...8 {
            for column in 0...8 {
                let point = CGPoint(x: box.minX + box.width * CGFloat(column) / 8, y: box.minY + box.height * CGFloat(row) / 8)
                if !above.contains(where: { $0.insetBy(dx: -0.5, dy: -0.5).contains(point) }) { return false }
            }
        }
        return true
    }

    /// The state its main window is in; nil without one. Hidden is the app's
    /// (Accessibility answers it as it is now); then minimised and full
    /// screen, the window's; else where the window server has it. On another
    /// desktop, never covered there: the window list doesn't keep another
    /// desktop's order (Deezer's, the front window there, read as covered).
    /// A closed window an app keeps counts as none.
    static func state(of app: NSRunningApplication) -> WindowState? {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1)
        if appElement.value(kAXHiddenAttribute) as? Bool == true { return .hidden }
        guard let info = mainWindow(of: pid) else { return nil }
        let element = element(of: pid, number: number(of: info))
        if element?.value(kAXMinimizedAttribute) as? Bool == true { return .minimised }
        if element?.value("AXFullScreen") as? Bool == true { return .fullScreen }
        if info[kCGWindowIsOnscreen as String] as? Bool == true { return isCovered(info) ? .covered : .visible }
        // Off screen on this very desktop: closed, as an Electron app keeps a
        // closed window (Deezer's, playing on), or ordered out.
        if let desktop = Desktops.of(window: number(of: info)), desktop == Desktops.all()?.current { return nil }
        return .otherDesktop
    }

    // SkyLight's front process, as window switchers (AltTab) read and set it:
    // from a process in the background, Accessibility's AXFrontmost and
    // NSRunningApplication.activate() answer success and change nothing, and
    // NSWorkspace's front app lags seconds in the process that changed it
    // (2026-10-12, in the VM). Resolved at runtime.
    private typealias GetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
    private typealias SetFrontProcess = @convention(c) (UnsafePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
    private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
    private typealias PIDForProcess = @convention(c) (UnsafePointer<ProcessSerialNumber>, UnsafeMutablePointer<pid_t>) -> Int32
    private static func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: type) }
    }
    private static let getFrontProcess = symbol("_SLPSGetFrontProcess", GetFrontProcess.self)
    private static let setFrontProcess = symbol("_SLPSSetFrontProcessWithOptions", SetFrontProcess.self)
    private static let processForPID = symbol("GetProcessForPID", ProcessForPID.self)
    private static let pidForProcess = symbol("GetProcessPID", PIDForProcess.self)

    /// The app in front now.
    static func frontPID() -> pid_t? {
        var process = ProcessSerialNumber(), pid: pid_t = 0
        if let getFrontProcess, let pidForProcess, getFrontProcess(&process) == 0, pidForProcess(&process, &pid) == 0, pid > 0 { return pid }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    /// Brings the process forward with `window` (its desktop shown), as a
    /// person's click would ("user generated"): whether it was asked.
    private static func setFront(_ pid: pid_t, window: Int) -> Bool {
        var process = ProcessSerialNumber()
        guard let setFrontProcess, let processForPID, processForPID(pid, &process) == 0 else { return false }
        return setFrontProcess(&process, UInt32(window), 0x200) == 0
    }

    /// Brings an app to the front, and to its window's desktop (`window`, when
    /// it must be on screen after; else its main window): through SkyLight,
    /// as window switchers do; else as `open` does, last, as a Safari web app
    /// may play again then (SoundCloud's did, 2026-10-11).
    @discardableResult
    static func activate(_ app: NSRunningApplication, showing window: Int? = nil) -> Bool {
        func there(within seconds: Double) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            repeat {
                let front = frontPID() == app.processIdentifier
                let shown = window.map { number in
                    infos(.optionOnScreenOnly).contains { WindowStates.number(of: $0) == number }
                } ?? true
                if front && shown { return true }
                Thread.sleep(forTimeInterval: 0.1)
            } while Date() < deadline
            return false
        }
        // The process forward, then its window above the others (SkyLight's
        // call alone left Deezer's window over Player Check's, 2026-10-12).
        if let number = window ?? mainWindow(of: app.processIdentifier).map(number(of:)),
           setFront(app.processIdentifier, window: number) {
            if let element = element(of: app.processIdentifier, number: number) {
                AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            }
            if there(within: 2) { return true }
        }
        if let url = app.bundleURL { bringForward(url) }
        return there(within: 2.5)
    }

    static func set(_ element: AXUIElement, _ attribute: String, _ on: Bool) {
        AXUIElementSetAttributeValue(element, attribute as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
    }

    static func setFrame(_ element: AXUIElement, _ frame: CGRect, size: Bool = true) {
        var origin = frame.origin, extent = frame.size
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        }
        if size, let value = AXValueCreate(.cgSize, &extent) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
    }

    /// Waits up to `seconds` for `done`.
    static func wait(_ seconds: Double, until done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }

    // MARK: Dragging it to another desktop

    private static func post(_ event: CGEvent?) {
        event?.post(tap: .cghidEventTap)
        usleep(40_000)
    }
    private static func mouse(_ type: CGEventType, at point: CGPoint) {
        post(CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: point,
                     mouseButton: .left))
    }

    /// Control-→ (or ←) as a keyboard sends it: Control pressed, the arrow
    /// with the Fn and number-pad flags arrows carry (macOS's desktop
    /// shortcuts are registered with them: without, it does nothing), then
    /// Control released with no flags. The flags of posted events stay in the
    /// system's keyboard state: without the release, every later click is a
    /// Control-click, which can't drag a window (2026-10-12).
    private static func controlArrow(right: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        func control(down: Bool) {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 59, keyDown: down)
            event?.type = .flagsChanged
            event?.flags = down ? .maskControl : []
            post(event)
        }
        control(down: true)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: right ? 124 : 123, keyDown: down)
            event?.flags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
            post(event)
        }
        control(down: false)
    }

    /// Shows the main display's desktop `id` as a person would, one Control-→
    /// or ← at a time; whether it's the current one after.
    static func showDesktop(_ id: Int) -> Bool {
        guard let all = Desktops.all(), let to = all.spaces.firstIndex(where: { $0.id == id }),
              let from = all.spaces.firstIndex(where: { $0.id == all.current }) else { return false }
        for _ in 0..<abs(to - from) {
            controlArrow(right: to > from)
            Thread.sleep(forTimeInterval: 0.9)
        }
        return wait(2, until: { Desktops.all()?.current == id })
    }

    /// Where the window can be held to drag it: right of its zoom button (a
    /// title bar), then along its top bar, at spots that aren't controls. An
    /// Electron app's top bar can be dragged only where its page marks it so,
    /// which Accessibility can't tell (Deezer's: right of its search field),
    /// so each spot is tried in turn.
    private static func grips(_ element: AXUIElement, _ box: CGRect) -> [CGPoint] {
        var points: [CGPoint] = []
        if let zoom = element.element(kAXZoomButtonAttribute)?.frame, zoom.width > 0 {
            points.append(CGPoint(x: zoom.maxX + 16, y: zoom.midY))
        }
        for y in [box.minY + 14, box.minY + 24] {
            var x = box.maxX - 40
            while x > box.minX + 80 {
                points.append(CGPoint(x: x, y: y))
                x -= 60
            }
        }
        let system = AXUIElementCreateSystemWide()
        let controls: Set<String> = [kAXButtonRole, kAXTextFieldRole, "AXSearchField", "AXLink", kAXCheckBoxRole, kAXPopUpButtonRole,
                                     kAXMenuButtonRole, kAXRadioButtonRole, kAXSliderRole, kAXComboBoxRole, kAXTextAreaRole, kAXImageRole]
        return points.filter { point in
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit else { return true }
            return !controls.contains(hit.text(kAXRoleAttribute)) && !hit.actions.contains(kAXPressAction)
        }
    }

    /// Drags the app's main window `steps` desktops right (left when
    /// negative), as a person would: it's brought forward, held at a spot of
    /// its top bar (a small drag towards the screen's middle shows the spot
    /// holds it), Control-→ or ← pressed, let go; the pointer goes back where
    /// it was. Once held, the window is dragged back to where it started before
    /// the desktop changes, so it lands in its place.
    /// `reveal` shows its page to Accessibility while it's in view (true), so
    /// the spots tried aren't its page's buttons, and hides it again after
    /// (false). Whether it got there.
    static func move(_ app: NSRunningApplication, desktops steps: Int, reveal: ((Bool) -> Void)? = nil) -> Bool {
        // Once more when no spot held it (SoundCloud's web app, just shown
        // again after hidden, held nowhere once, 2026-10-12).
        for attempt in 1...2 {
            if moveOnce(app, desktops: steps, reveal: reveal) { return true }
            log("  drag: attempt \(attempt) didn't take it there")
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    private static func moveOnce(_ app: NSRunningApplication, desktops steps: Int, reveal: ((Bool) -> Void)?) -> Bool {
        let pid = app.processIdentifier
        guard steps != 0, let info = mainWindow(of: pid), let start = Desktops.of(window: number(of: info)) else { return false }
        let shown = activate(app, showing: number(of: info))
        log("  drag: \(app.localizedName ?? "the app") brought forward: \(shown); in front: "
            + (frontPID().flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "?"))
        guard shown else { return false }
        Thread.sleep(forTimeInterval: 0.6)
        reveal?(true)
        defer { reveal?(false) }
        guard let element = element(of: pid, number: number(of: info)), let box = element.frame else { return false }
        let pointer = CGEvent(source: nil)?.location ?? .zero
        let direction: CGFloat = box.midX > (NSScreen.screens.first?.frame.midX ?? 0) ? -1 : 1
        var held = false
        let spots = grips(element, box)
        log(String(format: "  drag: window at %.0f,%.0f, %d spots to try", box.minX, box.minY, spots.count))
        for grip in spots {
            mouse(.mouseMoved, at: grip)
            mouse(.leftMouseDown, at: grip)
            for step in 1...3 { mouse(.leftMouseDragged, at: CGPoint(x: grip.x + direction * CGFloat(step) * 4, y: grip.y)) }
            usleep(150_000)
            held = element.frame.map { $0.minX != box.minX } ?? false
            log(String(format: "  drag: %@ at %.0f,%.0f", held ? "held" : "not held", grip.x, grip.y))
            if held {
                // Back where it started, held still, then to the other desktop.
                for step in [2, 1, 0] { mouse(.leftMouseDragged, at: CGPoint(x: grip.x + direction * CGFloat(step) * 4, y: grip.y)) }
                usleep(150_000)
                // A drag's first points don't move the window (macOS waits for
                // the pointer to go a little way first), so back at the grip it
                // can sit short of its place (VLC's, 4 pt, 2026-10-12): the
                // pointer goes on by what's missing until it's there.
                var at = grip
                for _ in 0..<3 {
                    guard let now = element.frame, now.origin != box.origin else { break }
                    at = CGPoint(x: at.x + box.minX - now.minX, y: at.y + box.minY - now.minY)
                    mouse(.leftMouseDragged, at: at)
                    usleep(150_000)
                }
                log(String(format: "  drag: held in place at %.0f,%.0f", element.frame?.minX ?? -1, element.frame?.minY ?? -1))
                for _ in 0..<abs(steps) {
                    controlArrow(right: steps > 0)
                    Thread.sleep(forTimeInterval: 0.9)
                }
                mouse(.leftMouseUp, at: at)
                break
            }
            mouse(.leftMouseUp, at: CGPoint(x: grip.x + direction * 12, y: grip.y))
        }
        CGWarpMouseCursorPosition(pointer)
        CGAssociateMouseAndMouseCursorPosition(1)
        Thread.sleep(forTimeInterval: 0.4)
        return held && Desktops.of(window: number(of: info)) != start
    }
}

/// An opaque window over the app's, from this tool: another window covering
/// it, as Chromium counts one (Deezer's page took no presses under it, as
/// under any window, 2026-10-12). Made while another desktop is current, it
/// lands there. AppKit's, so on the main thread only (the test's).
final class CoverWindow {
    private var window: NSWindow?
    var number: Int? { window.map { $0.windowNumber } }

    func show(over box: CGRect, naming name: String) {
        remove()
        MainActor.assumeIsolated {
            NSApplication.shared.setActivationPolicy(.accessory)
            let area = box.insetBy(dx: -20, dy: -20)
            let top = NSScreen.screens.first?.frame.height ?? 0
            let made = NSWindow(contentRect: NSRect(x: area.minX, y: top - area.maxY, width: area.width, height: area.height),
                                styleMask: .borderless, backing: .buffered, defer: false)
            made.isOpaque = true
            made.backgroundColor = .windowBackgroundColor
            made.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "Player Check covers \(name) here for its test")
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.frame = NSRect(x: 24, y: area.height / 2 - 12, width: area.width - 48, height: 24)
            made.contentView?.addSubview(label)
            made.orderFrontRegardless()
            made.display()
            window = made
        }
        settle()
    }

    /// AppKit shows (or takes away) the window once its transaction is
    /// committed, which happens as the run loop turns: this tool's waits
    /// don't turn it.
    private func settle() {
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }

    func remove() {
        guard window != nil else { return }
        MainActor.assumeIsolated {
            window?.orderOut(nil)
            window = nil
        }
        settle()
    }
}

/// A test's trip through the window states: where the app's window was
/// (put back at the end, or at a stop), the app to come back to before each
/// state's trials (the one running this tool, the Player Check app, else the
/// one in front at the start), and which states can be tested here.
final class WindowTest {
    let app: NSRunningApplication
    var pid: pid_t { app.processIdentifier }
    let home: NSRunningApplication?
    let original: WindowState
    private let originalFrame: CGRect
    private let originalDesktop: Int?
    private let homeDesktop: Int?
    /// The home app's window, when it was moved aside for the app's to show, and where it was.
    private var homeWindow: (element: AXUIElement, frame: CGRect)?
    private let cover = CoverWindow()
    /// Why each state that can't be tested isn't.
    var untested: [WindowState: String] = [:]
    /// Shows the app's page to Accessibility (its switch on) while its window
    /// is dragged, and hides it after: an Electron app's top bar has buttons
    /// Accessibility sees only then (Deezer's avatar).
    var revealPage: ((Bool) -> Void)?
    var states: [WindowState] { WindowState.allCases.filter { untested[$0] == nil } }

    init?(app: NSRunningApplication) {
        self.app = app
        let pid = app.processIdentifier
        guard let state = WindowStates.state(of: app), let info = WindowStates.mainWindow(of: pid) else { return nil }
        original = state
        originalFrame = WindowStates.element(of: pid, number: WindowStates.number(of: info))?.frame ?? WindowStates.frame(of: info)
        originalDesktop = Desktops.of(window: WindowStates.number(of: info))
        let parent = NSRunningApplication(processIdentifier: getppid())
        let front = WindowStates.frontPID().flatMap { NSRunningApplication(processIdentifier: $0) }
        home = parent?.activationPolicy == .regular ? parent : front?.processIdentifier == pid ? nil : front
        let desktops = Desktops.all()
        homeDesktop = desktops?.current
        // Full screen apps' desktops don't count: they go with their window.
        if desktops.map({ $0.spaces.filter { !$0.isFullScreen }.count < 2 }) ?? true {
            let why = desktops == nil ? "macOS's desktops can't be read" : "no other desktop: add one in Mission Control to test it"
            untested[.otherDesktop] = why
            untested[.otherDesktopCovered] = why
        }
    }

    private var element: AXUIElement? {
        WindowStates.mainWindow(of: pid).flatMap { WindowStates.element(of: pid, number: WindowStates.number(of: $0)) }
    }

    /// Back to the app the test came from, until its window is on screen: from
    /// a full screen app's desktop, its activating alone may leave that desktop
    /// shown (and the menu bar with it hidden).
    private func comeHome() {
        guard let home else { return }
        let window = WindowStates.mainWindow(of: home.processIdentifier).map(WindowStates.number(of:))
        for _ in 0..<2 {
            WindowStates.activate(home, showing: window)
            Thread.sleep(forTimeInterval: 0.8)
            // Shown still, once desktops stopped sliding.
            guard let window, !WindowStates.infos(.optionOnScreenOnly).contains(where: { WindowStates.number(of: $0) == window }) else { return }
        }
    }

    /// Shown, on this desktop, not minimised or full screen: the start of
    /// every other state (`removingCover` false at a stop: the cover is
    /// AppKit's, for the main thread, and goes with this tool anyway).
    private func normalize(removingCover: Bool = true) -> String? {
        if removingCover { cover.remove() }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1)
        if appElement.value(kAXHiddenAttribute) as? Bool == true {
            WindowStates.set(appElement, kAXHiddenAttribute, false)
            guard WindowStates.wait(3, until: { appElement.value(kAXHiddenAttribute) as? Bool != true }) else { return "it couldn't be shown again" }
        }
        // Out of sight and out of Accessibility's reach (VLC's window on
        // another desktop: no element number answered, 2026-10-12): its
        // desktop shown first, where its window can be reached; then it's
        // dragged back here as any other. Bringing VLC forward didn't show
        // that desktop (some of its hidden windows are on this one), so the
        // desktop is shown with Control-arrow, as a person would.
        if self.element == nil, let info = WindowStates.mainWindow(of: pid), info[kCGWindowIsOnscreen as String] as? Bool != true,
           let there = Desktops.of(window: WindowStates.number(of: info)), there != Desktops.all()?.current {
            guard WindowStates.showDesktop(there), WindowStates.wait(3, until: { self.element != nil }) else {
                comeHome()
                return "its window can't be reached, even with its desktop shown"
            }
        }
        guard let element else { return "its window can't be reached" }
        if element.value(kAXMinimizedAttribute) as? Bool == true {
            WindowStates.set(element, kAXMinimizedAttribute, false)
            guard WindowStates.wait(4, until: { element.value(kAXMinimizedAttribute) as? Bool != true }) else { return "it couldn't be unminimised" }
            Thread.sleep(forTimeInterval: 0.6)
        }
        if element.value("AXFullScreen") as? Bool == true {
            WindowStates.set(element, "AXFullScreen", false)
            guard WindowStates.wait(6, until: { element.value("AXFullScreen") as? Bool != true }) else { return "it couldn't leave full screen" }
            Thread.sleep(forTimeInterval: 1.2)
        }
        if let homeDesktop, let info = WindowStates.mainWindow(of: pid), let there = Desktops.of(window: WindowStates.number(of: info)),
           there != homeDesktop {
            guard let from = Desktops.index(of: there), let to = Desktops.index(of: homeDesktop) else {
                return "its window is on another display's desktop"
            }
            guard WindowStates.move(app, desktops: to - from, reveal: revealPage) else { return "its window couldn't be dragged back to this desktop" }
        }
        return nil
    }

    /// Visible: when covered, brought forward, with the home app in front
    /// again; when the home app's window still covers it, that one is moved
    /// aside (the user's choice, 2026-10-12), put back at the end.
    private func showVisible() -> String? {
        guard let info = WindowStates.mainWindow(of: pid) else { return "its window is gone" }
        guard WindowStates.isCovered(info) else { return nil }
        WindowStates.activate(app, showing: WindowStates.number(of: info))
        comeHome()
        guard let again = WindowStates.mainWindow(of: pid), WindowStates.isCovered(again) else { return nil }
        guard let home else { return "it's covered" }
        let homeApp = AXUIElementCreateApplication(home.processIdentifier)
        AXUIElementSetMessagingTimeout(homeApp, 1)
        guard let window = homeApp.element(kAXFocusedWindowAttribute) ?? homeApp.element(kAXMainWindowAttribute),
              let frame = window.frame else { return "it's covered" }
        if homeWindow == nil { homeWindow = (window, frame) }
        // Aside towards the side with room, leaving 160 pt of the app's window
        // in view; narrower when the screen is too small.
        let target = WindowStates.frame(of: again)
        let screen = NSScreen.screens.first?.visibleFrame ?? .zero
        var moved = frame
        if target.midX >= frame.midX {
            moved.origin.x = target.maxX - 160 - frame.width
            if moved.minX < screen.minX {
                moved.origin.x = screen.minX
                moved.size.width = max(400, target.maxX - 160 - screen.minX)
            }
        } else {
            moved.origin.x = target.minX + 160
            if moved.maxX > screen.maxX { moved.size.width = max(400, screen.maxX - moved.minX) }
        }
        WindowStates.setFrame(window, moved)
        Thread.sleep(forTimeInterval: 0.5)
        guard let after = WindowStates.mainWindow(of: pid), !WindowStates.isCovered(after) else {
            return "it's covered by \(home.localizedName ?? "the app in front")'s window, which couldn't be moved aside"
        }
        return nil
    }

    /// Puts the app's window in `state`, with the home app in front after;
    /// nil once it reads so, else why it couldn't be.
    func putIn(_ state: WindowState) -> String? {
        if let why = untested[state] { return why }
        let why: String?
        switch state {
        case .visible:
            why = normalize() ?? showVisible()
        case .covered:
            why = normalize() ?? showVisible() ?? coverIt()
        case .otherDesktop:
            why = normalize() ?? toOtherDesktop()
        case .otherDesktopCovered:
            let there = WindowStates.state(of: app) == .otherDesktop
            why = (there ? nil : normalize() ?? toOtherDesktop()) ?? coverOnItsDesktop()
        case .fullScreen:
            why = normalize() ?? setWindow("AXFullScreen", reads: .fullScreen, within: 6)
        case .minimised:
            why = normalize() ?? setWindow(kAXMinimizedAttribute, reads: .minimised, within: 4)
        case .hidden:
            why = normalize() ?? hide()
        }
        if let why { return why }
        comeHome()
        let now = WindowStates.state(of: app)
        // Covered on its desktop by this tool's window, there with it (the
        // window list can't tell covered there: `state(of:)`).
        if state == .otherDesktopCovered, now == .otherDesktop, let number = cover.number,
           let info = WindowStates.mainWindow(of: pid), Desktops.of(window: number) == Desktops.of(window: WindowStates.number(of: info)) {
            return nil
        }
        return now == state ? nil : "it reads as " + (now?.title ?? "having no window")
    }

    private func coverIt() -> String? {
        guard let info = WindowStates.mainWindow(of: pid) else { return "its window is gone" }
        cover.show(over: WindowStates.frame(of: info), naming: appName)
        return nil
    }

    /// To the nearest other desktop (the next first), chosen now: a full
    /// screen app's desktop between the two is passed by.
    private func toOtherDesktop() -> String? {
        guard let desktops = Desktops.all(), let here = desktops.spaces.firstIndex(where: { $0.id == desktops.current }) else {
            return "macOS's desktops can't be read"
        }
        let others = desktops.spaces.indices.filter { $0 != here && !desktops.spaces[$0].isFullScreen }
        guard let nearest = others.min(by: { abs($0 - here) < abs($1 - here) || (abs($0 - here) == abs($1 - here) && $0 > $1) }) else {
            return "no other desktop: add one in Mission Control to test it"
        }
        return WindowStates.move(app, desktops: nearest - here, reveal: revealPage) ? nil : "its window couldn't be dragged to another desktop"
    }

    private func coverOnItsDesktop() -> String? {
        guard let info = WindowStates.mainWindow(of: pid) else { return "its window is gone" }
        let number = WindowStates.number(of: info)
        // Brought forward there; else that desktop shown with Control-arrow
        // (VLC's coming forward didn't show it: `normalize`).
        if !WindowStates.activate(app, showing: number) {
            guard let there = Desktops.of(window: number), WindowStates.showDesktop(there) else { return "its desktop couldn't be shown" }
        }
        Thread.sleep(forTimeInterval: 0.6)
        return coverIt()
    }

    private func setWindow(_ attribute: String, reads state: WindowState, within seconds: Double) -> String? {
        guard let element else { return "its window can't be reached" }
        WindowStates.set(element, attribute, true)
        guard WindowStates.wait(seconds, until: { WindowStates.state(of: app) == state }) else { return "it didn't go \(state.title)" }
        if state == .fullScreen {
            // Its own desktop slides in for about a second: coming home meanwhile
            // leaves that desktop shown (and the menu bar hidden with it).
            let window = WindowStates.mainWindow(of: pid).map(WindowStates.number(of:))
            _ = WindowStates.wait(3, until: { window.flatMap(Desktops.of(window:)) == Desktops.all()?.current })
            Thread.sleep(forTimeInterval: 1)
        } else {
            Thread.sleep(forTimeInterval: 0.6)
        }
        return nil
    }

    private func hide() -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1)
        WindowStates.set(appElement, kAXHiddenAttribute, true)
        if !WindowStates.wait(2, until: { appElement.value(kAXHiddenAttribute) as? Bool == true }) { app.hide() }
        return WindowStates.wait(2, until: { appElement.value(kAXHiddenAttribute) as? Bool == true }) ? nil : "it couldn't be hidden"
    }

    /// Back as it was at the start: its state, place and desktop, the home
    /// app's window and the home app in front. What it couldn't put back, or nil.
    @discardableResult
    func restore(atStop: Bool = false) -> String? {
        var problem = normalize(removingCover: !atStop)
        if problem == nil, original != .fullScreen, let element { WindowStates.setFrame(element, originalFrame) }
        if problem == nil {
            switch original {
            case .otherDesktop, .otherDesktopCovered:
                if let originalDesktop, let homeDesktop, let from = Desktops.index(of: homeDesktop), let to = Desktops.index(of: originalDesktop),
                   !WindowStates.move(app, desktops: to - from, reveal: revealPage) {
                    problem = "its window couldn't be dragged back to its desktop"
                }
            case .fullScreen: problem = setWindow("AXFullScreen", reads: .fullScreen, within: 6)
            case .minimised: problem = setWindow(kAXMinimizedAttribute, reads: .minimised, within: 4)
            case .hidden: problem = hide()
            case .visible, .covered: break
            }
        }
        if let homeWindow { WindowStates.setFrame(homeWindow.element, homeWindow.frame) }
        if original != .hidden || home != nil { comeHome() }
        return problem
    }
}

/// The window state the test has the app in now: nil outside one (or before
/// the first). Out of view, a Chromium page's words lag (`wordsCurrent`).
var currentWindowState: WindowState?
/// The trip through the window states, for a test of an app with a window
/// (and the Accessibility permission to move it); why there's none otherwise.
var windowTest: WindowTest?
var windowStatesNote: String?
if testing, let running, AXIsProcessTrusted() {
    say()
    say("Window states")
    if let test = WindowTest(app: running) {
        windowTest = test
        stopState.restoreWindow = { test.restore(atStop: true) }
        if let hidden = hiddenInterface {
            let pid = running.processIdentifier
            test.revealPage = { on in
                guard let attribute = pageSwitch ?? hidden.switches.first else { return }
                if on {
                    if setSwitch(attribute, true, pid: pid), !stopState.switchesOn.contains(attribute) { stopState.switchesOn.append(attribute) }
                    _ = waitForPage(pid, seconds: 4)
                } else {
                    _ = setSwitch(attribute, false, pid: pid)
                }
            }
        }
        say("  each way is tested with its window in each state: " + WindowState.allCases.map(\.title).joined(separator: ", ")
            + "; it's put back as it is now: \(test.original.title)")
        for state in WindowState.allCases { if let why = test.untested[state] { say("  \(state.title): not tested (\(why))") } }
        stopState.setInTrial(true)
        let why = test.putIn(.visible)
        stopState.setInTrial(false)
        stopIfRequested()
        if let why {
            say("  not visible: \(why); its page is read as it is")
        } else {
            currentWindowState = .visible
            say("  visible now: its page is read in view, and the test starts there")
        }
    } else {
        windowStatesNote = "no window open"
        say("  not tested: no window open (each way is tried once, as it is)")
    }
}

say()
say("Page buttons")

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

/// AutoHush's Apple event codes (`ScriptablePlayer.Code`): the standard
/// suites', and the keywords of events, replies and object specifiers.
typealias EventCode = ScriptablePlayer.Code

/// A code read from a dictionary at run time as a number ("spfy" →
/// 0x73706679): ScriptablePlayers' `fourCharCode` takes only literals.
func osType(_ text: String) -> FourCharCode {
    text.utf8.prefix(4).reduce(0) { $0 << 8 | FourCharCode($1) }
}

/// The object specifier for the property `code` of `container`: of the
/// application as AutoHush builds it (`ScriptablePlayer.propertySpecifier`,
/// "player state"), else of what `container` names ("name of current
/// track", "playing of every document").
func propertySpecifier(_ code: String, of container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor {
    let specifier = ScriptablePlayer.propertySpecifier(osType(code))
    if let container { specifier.setDescriptor(container, forKeyword: EventCode.container) }
    return specifier
}

/// Whether macOS lets this tool (or the app running it) send the app Apple
/// events, asked before the first, as AutoHush asks when a player is chosen
/// (`AutomationPermission`): a send waits only 5 s, too short for someone
/// reading macOS's prompt. Allowed or denied, it's said once and kept; any
/// other answer (the app still starting: -600) is asked again before the
/// next event. Nil when allowed; else the error the event gets instead.
var automationAnswer: AutomationPermission?
func automationRefusal(pid: pid_t) -> NSError? {
    switch automationAnswer {
    case .allowed?: return nil
    case .denied?: return NSError(domain: NSOSStatusErrorDomain, code: Int(errAEEventNotPermitted))
    default: break
    }
    let status = AutomationPermission.check(pid: pid, ask: true)
    let answer = AutomationPermission(status: status)
    // A press's output is its one line of result: there it's only logged.
    let note = action == nil ? say : log
    switch answer {
    case .allowed:
        automationAnswer = answer
        note("  Automation for \(appName): allowed")
        return nil
    case .denied:
        automationAnswer = answer
        noteScriptError(-1743)
        note("  Automation for \(appName): not allowed: allow it in System Settings → Privacy & Security → Automation")
        return NSError(domain: NSOSStatusErrorDomain, code: Int(errAEEventNotPermitted))
    case .notAsked, .notRunning:
        return NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}

/// An Apple event error as AutoHush words it (`ScriptablePlayer.mapError`,
/// with the app's own message when it gave one), with macOS's number:
/// "error -1743 (Automation permission … not granted)".
func eventError(_ error: NSError) -> String {
    let mapped = ScriptablePlayer.mapError(number: error.code, message: error.userInfo[NSLocalizedFailureReasonErrorKey] as? String)
    if case .playerCommandFailed(.appleEventError(_, let message?)) = mapped { return "error \(error.code) (\(message))" }
    if case .playerCommandFailed = mapped { return "error \(error.code)" }
    return "error \(error.code) (\(mapped.localizedDescription))"
}

/// Sends the app the Apple event `makeEvent` builds for its process, as
/// AutoHush's `AppleEventChannel` sends one: to the running process, so an
/// event can never launch the app, waiting `AppleEventChannel.replyTimeout`
/// (5 s) for the reply, once Automation is allowed (`automationRefusal`).
/// The reply's direct object, or the error number, with the app's message
/// as `ScriptablePlayer.replyError` reads it (-1743: macOS refused it;
/// -600: it isn't running).
func sendAppleEvent(_ makeEvent: (pid_t) -> NSAppleEventDescriptor) -> Result<NSAppleEventDescriptor?, NSError> {
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { !$0.isTerminated })?
        .processIdentifier else { return .failure(NSError(domain: NSOSStatusErrorDomain, code: Int(procNotFound))) }
    if let refusal = automationRefusal(pid: pid) { return .failure(refusal) }
    do {
        let reply = try makeEvent(pid).sendEvent(options: [.waitForReply, .canInteract], timeout: AppleEventChannel.replyTimeout)
        if let number = reply.paramDescriptor(forKeyword: EventCode.errorNumber)?.int32Value, number != 0 {
            let message = reply.paramDescriptor(forKeyword: EventCode.errorString)?.stringValue
            return .failure(NSError(domain: NSOSStatusErrorDomain, code: Int(number),
                                    userInfo: message.map { [NSLocalizedFailureReasonErrorKey: $0] } ?? [:]))
        }
        return .success(reply.paramDescriptor(forKeyword: EventCode.directObject))
    } catch {
        return .failure(error as NSError)
    }
}

/// `get <property>` of the application, as AutoHush asks a player's state
/// or volume (`ScriptablePlayer.makeGetPropertyEvent`).
func getProperty(_ code: String) -> Result<NSAppleEventDescriptor?, NSError> {
    sendAppleEvent { ScriptablePlayer.makeGetPropertyEvent(osType(code), processIdentifier: $0) }
}

/// `set <property> to <value>` of the application, as AutoHush sets a
/// player's volume (`ScriptablePlayer.makeSetPropertyEvent`); nil once set.
func setProperty(_ code: String, to value: Int) -> NSError? {
    if case .failure(let error) = sendAppleEvent({ ScriptablePlayer.makeSetPropertyEvent(osType(code), to: value, processIdentifier: $0) }) {
        return error
    }
    return nil
}

/// `get` of what `specifier` names (a document's property, the current
/// track's name): AutoHush's get event with that direct object.
func getData(of specifier: NSAppleEventDescriptor) -> Result<NSAppleEventDescriptor?, NSError> {
    sendAppleEvent { pid in
        let event = ScriptablePlayer.makeCommandEvent(suite: EventCode.coreSuite, EventCode.getData, processIdentifier: pid)
        event.setParam(specifier, forKeyword: EventCode.directObject)
        return event
    }
}

/// One of its dictionary's commands by code ("spfyPaus": suite, then
/// command), as AutoHush sends pause and play (`ScriptablePlayer.makeCommandEvent`),
/// told which document to act on when it needs one; nil once sent.
func sendCommand(_ code: String, to target: NSAppleEventDescriptor? = nil) -> NSError? {
    let result = sendAppleEvent { pid in
        let event = ScriptablePlayer.makeCommandEvent(suite: osType(String(code.prefix(4))), osType(String(code.suffix(4))),
                                                      processIdentifier: pid)
        if let target { event.setParam(target, forKeyword: EventCode.directObject) }
        return event
    }
    if case .failure(let error) = result { return error }
    return nil
}

/// The object specifier for the app's documents: every one, or one by name
/// or by index (1: the front one), as AppleScript builds "document 1".
func documentSpecifier(named name: String? = nil, index: Int? = nil) -> NSAppleEventDescriptor {
    let record = NSAppleEventDescriptor.record()
    let specifier = record.coerce(toDescriptorType: EventCode.objectSpecifier) ?? record
    specifier.setDescriptor(NSAppleEventDescriptor(typeCode: osType(scripting?.documentClass ?? "docu")), forKeyword: EventCode.desiredClass)
    specifier.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: EventCode.container)
    if let name {
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: osType("name")), forKeyword: EventCode.keyForm)
        specifier.setDescriptor(NSAppleEventDescriptor(string: name), forKeyword: EventCode.keyData)
    } else {
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: osType("indx")), forKeyword: EventCode.keyForm)
        if let index {
            specifier.setDescriptor(NSAppleEventDescriptor(int32: Int32(index)), forKeyword: EventCode.keyData)
        } else {
            var all = osType("all ")
            specifier.setDescriptor(NSAppleEventDescriptor(descriptorType: osType("abso"), bytes: &all, length: 4)!,
                                    forKeyword: EventCode.keyData)
        }
    }
    return specifier
}

/// A reply's items: a list's, else the one value.
func items(_ descriptor: NSAppleEventDescriptor?) -> [NSAppleEventDescriptor] {
    guard let descriptor else { return [] }
    guard descriptor.descriptorType == typeAEList else { return [descriptor] }
    return descriptor.numberOfItems > 0 ? (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0) } : []
}

/// Its open documents by script (QuickTime Player's), front first: each
/// one's name and whether it's playing.
func scriptedDocuments() -> Result<[(name: String, playing: Bool)], NSError> {
    guard let playing = scripting?.documentPlaying else { return .success([]) }
    let every = documentSpecifier()
    switch (getData(of: propertySpecifier("pnam", of: every)), getData(of: propertySpecifier(playing, of: every))) {
    case (.failure(let error), _), (_, .failure(let error)):
        return .failure(error)
    case (.success(let names), .success(let flags)):
        return .success(zip(items(names), items(flags)).map { ($0.stringValue ?? "", $1.booleanValue) })
    }
}

/// The documents a test's pause paused, by name: its play plays them again.
var pausedDocuments: [String] = []

/// The app's state by script, when its dictionary has it and it answers:
/// its `player state` (stopped, playing, paused, as Spotify's, read as
/// AutoHush reads it: `ScriptablePlayer.playerState(fromEnumCode:)`, which
/// counts Music's fast forwarding and rewinding as playing), else its
/// `playing` flag (VLC's: playing or paused), else its documents'
/// (QuickTime Player's: playing while one is, stopped with none open),
/// asked by Apple event. Only macOS refusing it (-1743: no Automation
/// permission for whatever runs this tool) stops the asking; another error
/// (a timeout, -1712, from a busy VLC) counts for that look only. Each kind
/// of error is said once.
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
    switch getProperty(property) {
    case .failure(let error):
        return failed(error)
    case .success(let result):
        guard let result else { return nil }
        guard scripting.hasPlayerState else {
            if result.booleanValue { return "playing" }
            // Not playing: VLC's `current time` is -1 with no item, so it's
            // stopped, else paused, as AutoHush's VLCPlayer tells them apart.
            guard let time = scripting.properties.first(where: { $0.value == "current time" })?.key,
                  case .success(let reply?) = getProperty(time)
            else { return "paused" }
            let state = VLCPlayer.state(playing: false, currentTime: Int(reply.int32Value))
            return state == .unknown ? "paused" : state.rawValue
        }
        let code = result.enumCodeValue
        let state = ScriptablePlayer.playerState(fromEnumCode: code)
        if state != .unknown { return state.rawValue }
        // A value AutoHush doesn't know: its code, as the app gave it.
        return String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, encoding: .macOSRoman) ?? "?"
    }
}

/// The name of what it plays, by Apple event, when its dictionary has a
/// `current track` (Spotify's, Music's, TV's), else a `name of current item`
/// (VLC's). It stays while paused, where a window's title may not (a paused
/// Spotify's says "Spotify Premium"), and it's read wherever its window is
/// (VLC's on another desktop can't be reached by Accessibility, 2026-10-12).
/// Nil without one, or when it doesn't answer (nothing loaded).
func scriptedSong() -> String? {
    guard let scripting, scripting.namesItsSong, scriptError == nil else { return nil }
    let specifier = scripting.hasCurrentTrack || scripting.currentItemName == nil
        ? propertySpecifier("pnam", of: propertySpecifier("pTrk")) : propertySpecifier(scripting.currentItemName!)
    switch getData(of: specifier) {
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
        if let error = sendCommand(code) { return failed(error) }
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
        if let error = sendCommand(code, to: target) { return failed(error) }
    }
    return true
}

/// Whether its volume can be read and set as fades need it, checked once
/// while a test has it paused (silent): its `sound volume` (Spotify's,
/// Music's), else its `audio volume` (VLC's, 0–512), set one step away and
/// read back, then put back. An app that reads back another number than it
/// was set to (Spotify: one less) needs the profile's `readVolume`, or each
/// fade restoring the volume it read loses a step. It's put back however
/// the change went: a change refused or not read back may still have taken.
var volumeChecked = false
func checkVolume() {
    guard !volumeChecked, let scripting,
          let (code, name) = scripting.properties.first(where: { $0.value == "sound volume" })
              .map({ ($0.key, $0.value) }) ?? scripting.properties.first(where: { $0.value == "audio volume" }).map({ ($0.key, $0.value) })
    else { return }
    volumeChecked = true
    func read() -> Int? {
        guard case .success(let reply?) = getProperty(code) else { return nil }
        return Int(reply.int32Value)
    }
    guard let start = read() else { say("    volume ('\(name)'): can't be read: no fades"); return }
    let target = start > 1 ? start - 1 : start + 1
    let setError = setProperty(code, to: target)
    // Music drops a change that follows another within a moment (measured:
    // set 99 then 100 at once, it stays at 99; 0.2 s apart, it takes both).
    Thread.sleep(forTimeInterval: 0.3)
    let back = read()
    // Put back as it was: an app that reads one less is set one more.
    let offset = setError == nil ? (back.map { $0 - target } ?? 0) : 0
    var restored = back
    for _ in 0..<2 where restored != start {
        _ = setProperty(code, to: start - offset)
        Thread.sleep(forTimeInterval: 0.3)
        restored = read()
    }
    let putBack = restored == start ? "; put back to \(start)"
        : "; couldn't put it back: it reads \(restored.map(String.init) ?? "?") (was \(start))"
    if let setError {
        say("    volume ('\(name)'): \(start), can't be set (\(eventError(setError))): no fades" + (back == start ? "" : putBack))
        return
    }
    guard let back else { say("    volume ('\(name)'): set to \(target), then can't be read: no fades" + putBack); return }
    say("    volume ('\(name)'): \(start); set to \(target), it reads \(back): "
        + (offset == 0 ? "reads back as set, so it can fade"
           : "reads \(abs(offset)) \(offset < 0 ? "less" : "more") than set (as Spotify, one less): the profile needs readVolume")
        + putBack
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
    /// Whether `pageToggle`'s word is current (`pageWordCurrent`); a stale
    /// one is shown, but nothing is judged by it.
    var pageCurrent = true
    var sounding: Bool
    /// Heard by its level; nil when not measured.
    var audible: Bool? = nil
    /// As its keep-awake assertions tell it (`awake`); nil while they don't.
    var awake: Bool? = nil
    /// Stopped, as its surest state tells it: its scripted state, else what
    /// it reports to Now Playing, else its menu's item (disabled). A track
    /// that ends leaves it so (VLC's said stopped, not paused).
    var stopped: Bool {
        if let state { return state == "stopped" }
        if let reported { return reported == "Stopped" }
        return menuState == "stopped"
    }
    var line: String {
        [menuTitle.map { "menu '\($0)'" + (menuState == "stopped" ? " (disabled)" : "") }, state.map { "state \($0)" }, reported.map { "reports \($0.lowercased())" },
         pageToggle.map { "page '\($0)'" + (pageCurrent ? "" : " (out of sight: its word lags)") }, "sound \(sounding ? "on" : "off")",
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
                pageToggle: page?.toggle == nil ? nil : pageToggleLabel(pid), pageCurrent: pageWordCurrent,
                sounding: sounding, audible: level ? audible(pid) : nil, awake: awake(pid, sounding: sounding))
}

/// Whether a page button's words are current: a WebKit page keeps them so
/// anywhere; a Chromium or Flutter page only while its window is on screen
/// (this desktop, not hidden or minimised): out of sight an Electron page
/// lags a state (Deezer's said Pause while paused). In a test's window
/// state other than visible, never (a button's `onScreen` is from the read).
func wordsCurrent(_ button: FoundButton) -> Bool {
    pageIsWebKit || (button.onScreen && (currentWindowState ?? .visible) == .visible)
}

/// Whether the page's Play/Pause word can be judged by now (`wordsCurrent`).
var pageWordCurrent: Bool { page?.toggle.map(wordsCurrent) ?? false }

/// For a press, whether its page's player bar shows the app's state by its
/// button's word (`pageWordCurrent`). Then what it reports to Now Playing
/// isn't read (opening macOS's log and reading back to when the app opened:
/// 1.4–2 s). Out of sight, an Electron page's word is stale, so there the
/// log is read.
var barShowsState: Bool {
    pressingOneWay && page?.withControls == true && pageWordCurrent
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
    guard levelsAllowed, quick.state == nil, quick.reported == nil, quick.pageToggle == nil || !quick.pageCurrent else { return quick }
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

/// Set by `trial` when, after its play, the app read stopped where its pause
/// had left it paused: its track ended meanwhile (the 61 s test track did,
/// 2026-10-12), so the trial says nothing about the way and is run again.
var trialTrackEnded = false

/// Whether a press took, judged by the surest sign the app had before it:
/// its scripted state, else what it reports to Now Playing, else its page's
/// button (Play while paused; while its word is current), else its level (as AutoHush hears it), else
/// its keep-awake assertion (as AntiDot mode reads it), else its menu's
/// state (as AutoHush's MenuPlayer reads it), else its menu's word changing
/// or its sound. (Deezer's menu word changes late by itself: it said Play
/// while playing, then Pause a second later, with nothing pressed.)
struct Sign {
    let before: Look
    var byState: Bool { before.state != nil }
    var byReport: Bool { !byState && before.reported != nil }
    /// Only while its word is current: a stale one would hide the pause.
    var byPage: Bool { !byState && !byReport && before.pageToggle != nil && before.pageCurrent }
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
/// the state notifications announced is said after each. A play that didn't
/// take is pressed once more (still a failure, said so in `trialProblem`); a
/// track that ended meanwhile sets `trialTrackEnded`. A stop meanwhile waits
/// until it plays again.
func trial(_ label: String, pid: pid_t, pause: () -> Bool, play: () -> Bool, undo: (() -> Void)? = nil,
           whilePaused: (() -> Void)? = nil) -> TrialResult {
    stopState.setInTrial(true)
    defer { stopState.setInTrial(false) }
    trialTrackEnded = false
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
    /// Once more, before anyone is asked (the user, 2026-10-12: "Implement 1
    /// and 2"): a play it missed shows as such, and still fails the way. Not
    /// when it plays by now (a toggle would pause it again).
    func pressedOnceMore() -> TrialResult {
        let now = look(pid, level: sign.byLevel)
        guard !playing(now) else {
            say("    now: \(now.line) → it plays: its play took late")
            trialProblem = "it paused, but played again only after more than 4 s"
            return .pausedOnly
        }
        guard play() else {
            say("    pressed once more: couldn't play it again either")
            return .pausedOnly
        }
        let second = waitFor(4, pid: pid, level: sign.byLevel, until: playing)
        if playing(second) {
            say("    pressed once more: \(second.line) → it plays: the first didn't take")
            trialProblem = "it paused, but played again only when pressed a second time" + (trialProblem.map { " (the first: \($0))" } ?? "")
        } else if second.stopped, !after.stopped {
            say("    pressed once more: \(second.line) → it stopped: its track ended meanwhile")
            trialTrackEnded = true
        } else {
            say("    pressed once more: \(second.line) → it didn't play either")
        }
        return .pausedOnly
    }
    let playedAt = Date()
    guard play() else {
        say("    couldn't play it again")
        return pressedOnceMore()
    }
    let back = waitFor(4, pid: pid, level: sign.byLevel, until: playing)
    let again = playing(back)
    if !again, back.stopped, !after.stopped {
        say("    after playing again: \(back.line) → it stopped: its track ended meanwhile")
        trialTrackEnded = true
        return .pausedOnly
    }
    say("    after playing again: \(back.line) → " + (again ? "it plays" : "it didn't play again in 4 s"))
    announcementLine(since: playedAt).map { say($0) }
    if let pauseAnnounced, notifications?.announced(since: playedAt).last.map({ $0.state == .playing && $0.name == pauseAnnounced }) == true {
        announcingNotification = announcingNotification ?? pauseAnnounced
    }
    return again ? .worked : pressedOnceMore()
}

/// Whether it plays, as far as can be seen, in `Sign`'s order: its scripted
/// state, else what it reports to Now Playing, else its page's button (Pause
/// while it plays; while its word is current), else its level, else its keep-awake assertion, else its
/// menu's state, else its sound output (which an Electron app or a web app
/// keeps a few seconds after a pause, VLC a minute).
func isPlaying(_ pid: pid_t) -> Bool {
    let now = look(pid)
    if let state = now.state { return state == "playing" }
    if let reported = now.reported { return reported == "Playing" }
    if let toggle = now.pageToggle, now.pageCurrent { return wordSays(toggle) == .playing }
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
/// can't be read (not an administrator), or while it reported nothing since then.
func reportedState() -> String? {
    guard canBeNowPlaying, isAdministrator, let running else { return nil }
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
    if let pid = running?.processIdentifier { waitForFullerMode(pid: pid) }
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
/// Why the panel's item in the menu bar wasn't found: it's found and pressed
/// through Accessibility, so without that permission, that's why.
var noPanelItem: String {
    AXIsProcessTrusted()
        ? "no Now Playing item in the menu bar (it shows once something has played, unless System Settings → Control Center hides it)"
        : "this tool (or the app running it) needs the Accessibility permission: the panel is found and pressed through it"
}
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

/// Keeps the row just pressed as the app's, between runs, once the app
/// changed with it: a later press finds it by its text when nothing shows
/// the app's song (a Play after a Pause, as a check's play does within one
/// run; VLC's window on another desktop gives no title, 2026-10-12).
func rememberPanelRow() {
    guard let panelRowText, savedButtons()[bundleID]?.panelRow != panelRowText else { return }
    saveButton { $0.panelRow = panelRowText }
}

/// The one row whose text is the app's remembered row's, if exactly one is.
func rememberedRow(_ rows: [PanelRow]) -> PanelRow? {
    guard let text = savedButtons()[bundleID]?.panelRow else { return nil }
    let same = rows.filter { $0.text == text }
    return same.count == 1 ? same[0] : nil
}

/// Which row to press: the app's; the one pressed last, else the app's; or
/// only the one pressed last (to put back a press that changed it).
enum PanelRowChoice { case app, lastElseApp, lastOnly }

/// Opens the panel, presses the Play/Pause of a row (the row shows Pause
/// when `pausing`, Play otherwise) and closes it; true once pressed. The
/// rows don't name their apps (only an icon shows it), so the app's row is
/// the one showing its song (`appRows`: by its windows' titles, its page's
/// player bar or what it plays by AppleScript); else the row it changed with
/// before (`rememberedRow`); while pausing, else the only row playing when
/// the app is the Now Playing one. Nothing is pressed
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
        panelProblem = noPanelItem
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
        // Its song first; else the row it changed with before; else, pausing, the only one playing.
        row = mine.count == 1 ? mine[0] : !mine.isEmpty ? nil
            : rememberedRow(candidates) ?? (holdsNowPlaying && candidates.count == 1 ? candidates[0] : nil)
    }
    guard let row else {
        let state = pausing ? "Pause" : "Play"
        panelProblem = rows.isEmpty ? "the panel showed no rows"
            : choice == .lastOnly ? "the row pressed before ('\(panelRowText ?? "")') no longer shows \(state)"
            : mine.count > 1 ? "\(mine.count) of the panel's rows with \(state) show \(appName)'s song: which is its own can't be told"
            : "none of the panel's \(candidates.count) rows with \(state) shows \(appName)'s song (read from "
                + (["its windows' titles"] + (page?.toggle != nil ? ["its player bar"] : [])
                    + (scripting?.namesItsSong == true ? ["what it plays, by AppleScript"] : [])).joined(separator: " or ")
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
/// in its windows' titles or what it plays by AppleScript (Deezer's title,
/// Spotify's current track and VLC's current item name it), else as the row
/// it changed with before (`rememberedRow`); only when none matches is its page read, for
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
        panelProblem = noPanelItem
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
    // Else the row it changed with before, before reading its page (seconds).
    if mine.isEmpty, let remembered = rememberedRow(rows) { mine = [remembered] }
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
                + (scripting?.namesItsSong == true ? ["what it plays, by AppleScript"] : [])).joined(separator: " or ")
            + ") or its name; the rows don't name their apps"
    return .notPressed
}

// MARK: The test

/// Each way's result: in the first window state tested (visible), or the
/// only run when there were no states.
var scriptResult: TrialResult?
var menuResult: TrialResult?
var pageResult: TrialResult?
var panelResult: TrialResult?
/// Each way's result in each window state ("script", "menu", "page",
/// "panel"), and why it failed there, for "Ways to control it".
var stateResults: [String: [(state: WindowState, result: TrialResult, why: String)]] = [:]
/// Why the trial running failed, as its press said (no button to press…).
var trialProblem: String?
/// Why a way's trial failed in a window state: what's known of the state
/// (an Electron page out of view), else what its press said, else the trial's.
func whyFailed(_ way: String, in state: WindowState, _ result: TrialResult) -> String {
    if way == "page", isElectron, launchedWithOption == false, [.covered, .otherDesktop, .otherDesktopCovered, .fullScreen].contains(state) {
        return "Chromium neither builds nor presses a page whose window is fully out of view; \(appName) wasn't opened with"
            + " \(LaunchOption.occludedWindows)"
    }
    if let trialProblem { return trialProblem }
    return result == .pausedOnly ? "it paused, but didn't play again" : "pressing it changed nothing"
}
/// Why a way wasn't tried, for "Ways to control it".
var notTried = readOnly ? "not tried: read only" : "not tried"
var notifications: NotificationLog?
if testing {
    say()
    say("Press test")
    let script = scriptControls()
    if running == nil {
        say("  not run: the app isn't running")
    } else if script == nil, menu == nil, page?.toggle == nil, !canBeNowPlaying || !AXIsProcessTrusted() {
        // Nothing to press, and nothing for the panel to reach (or no
        // Accessibility to reach it with): asking for it to play would only wait.
        say("  not run: nothing to press (no AppleScript play or pause, playback menu or page button), and "
            + (canBeNowPlaying ? "without the Accessibility permission the Now Playing panel can't be reached" : notNowPlaying))
        notTried = "not tried: nothing to press"
    } else if let running {
        let pid = running.processIdentifier
        notifications = NotificationLog(bundleID: bundleID)
        /// The window state the trials run in, and whether it's the first
        /// tested (learning the page's button and the volume check happen there).
        var state: WindowState?
        var first = true
        /// Whether the trial's pause pressed the player's own button (learned,
        /// or with a player's slider around it), so a pause that didn't take
        /// was the site's refusal, not a wrong button.
        var pressedPlayersPause = false
        func pressPage(pausing: Bool) -> Bool {
            guard let button = pageButtonToPress(pid: pid, pausing: pausing) else {
                let shown = !(pageButtons(pid: pid) ?? []).isEmpty
                say("    " + (shown ? "no button in sight to press" : "its page didn't show"))
                trialProblem = shown ? "its page showed no Play/Pause to press"
                    : "its page didn't show" + (pageSwitch.map { " with \(switchName($0)) on" } ?? "")
                return false
            }
            var why: String?
            guard pressPageButton(button, pausing: pausing, why: &why) else {
                if let why { say("    \(why)") }
                trialProblem = why
                return false
            }
            if pausing {
                let players = [learned?.element, page?.withControls == true ? page?.toggle?.element : nil, barToggle].compactMap { $0 }
                pressedPlayersPause = players.contains { CFEqual($0, button.element) }
            }
            return true
        }
        /// After the first window state, the page is pressed as Player Check's
        /// own presses press it (the user, 2026-10-12: "Go with A"): its switch
        /// off between presses, each press turning it on, giving the page up to
        /// 4 s to show, and turning it off once it's seen whether it took.
        /// Kept on instead, a page built in view stays usable out of view
        /// (Deezer's passed every state), which those presses don't get. The
        /// first state keeps it on, for learning the button. Only a switch
        /// this tool may turn off: Electron's, or one it turned on.
        let pressSwitch: String? = pageSwitch.flatMap { $0 == manualAccessibility || stopState.switchesOn.contains($0) ? $0 : nil }
        /// Left on by the check (the page was readable already): on again at the end.
        let pressSwitchLeftOn = pressSwitch.map { !stopState.switchesOn.contains($0) } ?? false
        func switchForPress(_ on: Bool) {
            guard let pressSwitch, !first else { return }
            if on {
                if setSwitch(pressSwitch, true, pid: pid), !stopState.switchesOn.contains(pressSwitch) {
                    stopState.switchesOn.append(pressSwitch)
                }
                _ = waitForPage(pid, seconds: 4)
            } else {
                _ = setSwitch(pressSwitch, false, pid: pid)
            }
        }
        let panelReachable = canBeNowPlaying && AXIsProcessTrusted()
        /// Each way's play, to play it again quietly when a way left it paused.
        var plays: [(way: String, title: String, play: () -> Bool)] = []
        if let script { plays.append(("script", "AppleScript", { sendScript(script.play) })) }
        if menu != nil { plays.append(("menu", "its menu", { pressMenuToggle(pid: pid) })) }
        plays.append(("page", "its page's button", {
            guard page?.toggle != nil else { return false }
            switchForPress(true)
            return pressPage(pausing: false)
        }))
        if panelReachable { plays.append(("panel", "the Now Playing panel", { pressInPanel(pid: pid, pausing: false) })) }
        /// Whether a trial has run (before the first, whoever runs the check
        /// starts it), and the way whose trial ran last (its play was pressed
        /// twice already).
        var trialRan = false
        var lastWay: String?
        /// Whether a way worked in this window state (with no window, in the one run).
        func workedHere(_ way: String) -> Bool {
            guard let state else {
                return [("script", scriptResult), ("menu", menuResult), ("page", pageResult), ("panel", panelResult)]
                    .contains { $0.0 == way && $0.1 == .worked }
            }
            return stateResults[way]?.contains { $0.state == state && $0.result == .worked } == true
        }
        /// A way that left it paused, or a track that ended: before anyone
        /// is asked, in any state, it's played again by a way that worked in
        /// this state, else by the others (the user, 2026-10-12: "Implement 1
        /// and 2"): AppleScript, its menu, then the panel, a last resort as it
        /// shows on screen. Each only while it doesn't play (a toggle would
        /// pause it).
        func playAgain() -> Bool {
            let here = plays.filter { workedHere($0.way) }
            let others = plays.filter { play in
                ["script", "menu", "panel"].contains(play.way) && play.way != lastWay && !here.contains { $0.way == play.way }
            }
            for play in here + others {
                guard !isPlaying(pid) else { return true }
                guard play.play() else { continue }
                _ = waitFor(4, pid: pid, until: { _ in isPlaying(pid) })
                if play.way == "page" { switchForPress(false) }
                if isPlaying(pid) {
                    say("    played again by \(play.title)")
                    return true
                }
            }
            return false
        }
        // Each way needs it playing: whoever runs the tool is asked to start
        // it before the first, and whenever a way leaves it stopped and it
        // can't be played again otherwise.
        var going = true
        func ready() -> Bool {
            guard going else { return false }
            if trialRan, !isPlaying(pid), playAgain() {
                if first { noteLearningPlaying(pid: pid) }
                return true
            }
            going = waitUntilPlaying(pid)
            if !going {
                notTried = "not tried: it didn't play"
                say("  stopped: \(appName) didn't play within 2 minutes")
            } else if first {
                // Its page while it plays, to learn its Play/Pause from the first pause.
                noteLearningPlaying(pid: pid)
            }
            return going
        }
        func record(_ way: String, _ result: TrialResult) {
            if first {
                switch way {
                case "script": scriptResult = result
                case "menu": menuResult = result
                case "page": pageResult = result
                default: panelResult = result
                }
            }
            if let state { stateResults[way, default: []].append((state, result, whyFailed(way, in: state, result))) }
            trialProblem = nil
            trialRan = true
            lastWay = way
        }
        /// A trial whose track ended meanwhile (`trialTrackEnded`) is run
        /// again once it plays (`ready`): it said nothing about the way. Ended
        /// twice, it fails saying so.
        func trialAgainIfEnded(_ way: String, _ run: () -> TrialResult) -> TrialResult {
            let result = run()
            guard trialTrackEnded else { return result }
            trialRan = true
            lastWay = way
            say("    its track ended during the trial: once more, once it plays")
            guard ready() else {
                trialProblem = "its track ended during the trial, and it didn't play again"
                return result
            }
            trialProblem = nil
            let again = run()
            if trialTrackEnded { trialProblem = "its track ended during the trial, twice: play a longer one and check again" }
            return again
        }
        let states: [WindowState?] = windowTest.map { $0.states } ?? [nil]
        for (index, next) in states.enumerated() where going {
            stopIfRequested()
            state = next
            if let next, let windowTest {
                say("  State \(index + 1) of \(states.count): \(next.title)")
                // Off, as between two presses, before the window goes.
                switchForPress(false)
                stopState.setInTrial(true)
                let why = windowTest.putIn(next)
                stopState.setInTrial(false)
                stopIfRequested()
                if let why {
                    say("    not tested: \(why)")
                    windowTest.untested[next] = why
                    continue
                }
                currentWindowState = next
            }
            trialProblem = nil
            if let script, scriptProblem == nil, ready() {
                // A toggle is sent for the pause only while it plays, and again to play.
                record("script", trialAgainIfEnded("script") {
                    trial("by script (\(script.pause), \(script.play))", pid: pid,
                          pause: { sendScript(script.pause) }, play: { sendScript(script.play) },
                          whilePaused: first ? { checkVolume(); learnPageButton(pid: pid) } : nil)
                })
                stopIfRequested()
                RunLoop.main.run(until: Date().addingTimeInterval(1))
            }
            if menu != nil, ready() {
                record("menu", trialAgainIfEnded("menu") {
                    trial("by its menu", pid: pid, pause: { pressMenuToggle(pid: pid) }, play: { pressMenuToggle(pid: pid) },
                          whilePaused: first ? { learnPageButton(pid: pid) } : nil)
                })
                stopIfRequested()
                RunLoop.main.run(until: Date().addingTimeInterval(1))
            }
            // No other way paused it and no button is named Play or Pause: as
            // AutoHush asks ("It's Paused"), whoever runs the check pauses it, and
            // the button whose words changed is learned (the user's choice, 2026-10-12).
            let pausedByAnother = [scriptResult, menuResult].contains { $0 == .worked || $0 == .pausedOnly }
            if first, learned == nil, !pausedByAnother, page?.toggle == nil, page?.buttons ?? 0 > 0, ready() {
                if !learner.hasPlayed {
                    // Its page is out of sight, where its words can't be learned: nobody is asked.
                    learnPageButton(pid: pid)
                } else {
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
            }
            if page?.toggle != nil, ready() {
                let result = trialAgainIfEnded("page") {
                    pressedPlayersPause = false
                    return trial("by its page's " + (learned == nil ? "button" : "learned button"), pid: pid,
                                 pause: { switchForPress(true); return pressPage(pausing: true) },
                                 play: { switchForPress(true); return pressPage(pausing: false) },
                                 undo: { switchForPress(false) },
                                 whilePaused: first ? { learnPageButton(pid: pid) } : { switchForPress(false) })
                }
                switchForPress(false)
                if result == .didNotPause, pressedPlayersPause, (state ?? .visible) == .visible {
                    say("    a pause its page refuses: AutoHush would mute it instead")
                }
                record("page", result)
                stopIfRequested()
                RunLoop.main.run(until: Date().addingTimeInterval(1))
            }
            if !canBeNowPlaying {
                if first {
                    panelProblem = panelNotNowPlaying
                    say("  the Now Playing panel: not pressed: \(notNowPlaying)")
                    panelResult = .didNotPause
                }
            } else if !AXIsProcessTrusted() {
                if first { say("  the Now Playing panel: not pressed: \(noPanelItem)") }
            } else if ready() {
                let result = trialAgainIfEnded("panel") {
                    panelProblem = nil
                    return trial("by the Now Playing panel", pid: pid, pause: { pressInPanel(pid: pid, pausing: true) },
                                 play: { pressInPanel(pid: pid, pausing: false, choice: .lastElseApp) },
                                 undo: {
                                     // The row pressed may have been another app's: pressed again, that app plays on.
                                     if panelRowText != nil { _ = pressInPanel(pid: pid, pausing: false, choice: .lastOnly) }
                                 },
                                 whilePaused: first ? { learnPageButton(pid: pid) } : nil)
                }
                if let panelProblem {
                    say("    \(panelProblem)")
                    // Its own reason, unless its play took only when pressed once more.
                    trialProblem = trialProblem ?? panelProblem
                }
                // It paused with that row: its own, for later presses.
                if result != .didNotPause { rememberPanelRow() }
                record("panel", result)
                stopIfRequested()
            }
            first = false
        }
        if let windowTest {
            stopState.setInTrial(true)
            let problem = windowTest.restore()
            stopState.setInTrial(false)
            stopState.restoreWindow = nil
            currentWindowState = nil
            // Read again: another app's windows that covered it may be behind it now.
            let now = WindowStates.state(of: running)
            say(now == windowTest.original || problem != nil
                ? "  its window put back as it was (\(windowTest.original.title))" + (problem.map { ", but \($0)" } ?? "")
                : "  its window put back where it was, but it was \(windowTest.original.title) and it's \(now?.title ?? "gone") now")
            stopIfRequested()
        }
        if pressSwitchLeftOn, let pressSwitch, setSwitch(pressSwitch, true, pid: pid) {
            stopState.switchesOn.removeAll { $0 == pressSwitch }
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
                learnFromPress(button, before: button.label, pausing: pausing)
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
                rememberPanelRow()
                say("\(pausing ? "Paused" : "Played") it with its row in the Now Playing panel ('\(panelRowText ?? "")').")
                finish(0)
            case .notPressed:
                tried.append(panelProblem ?? "couldn't press its row in the Now Playing panel")
                continue
            case .pressed:
                break
            }
            if within({ isPlaying(pid) != pausing }) {
                rememberPanelRow()
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
/// and played again in the test, in every window state tested; ⚠ in some
/// (the states where it didn't, and why, on the lines under it); ✗ in none,
/// or not there; ? found but not tried (read only, or it didn't play); –
/// not checked. The Player Check app shows this section as a checklist.
func way(_ mark: String, _ text: String) { say("  \(mark) \(text)") }
say()
say("Ways to control it")
/// A way's results in the window states, when the test went through them:
/// its mark, what its line adds, and a line per state it failed in (only
/// for ⚠: a ✗ failed in all) or that wasn't tested.
func stateSummary(_ key: String) -> (mark: String, suffix: String, lines: [String])? {
    guard let windowTest, let results = stateResults[key], !results.isEmpty else { return nil }
    let passed = results.filter { $0.result == .worked }.count
    let mark = passed == results.count ? "✓" : passed == 0 ? "✗" : "⚠"
    let all = WindowState.allCases.count
    let suffix = passed == results.count
        ? " (" + (passed == all ? "all \(all) window states" : passed == 1 ? "the one window state tested" : "the \(passed) window states tested") + ")"
        : passed == 0 ? " (in every window state tested)" : ", in \(passed) of \(results.count) window states"
    var lines = mark == "⚠" ? results.filter { $0.result != .worked }.map { "      ✗ \($0.state.title): \($0.why)" } : []
    for state in WindowState.allCases where !results.contains(where: { $0.state == state }) {
        lines.append("      – \(state.title): not tested (\(windowTest.untested[state] ?? notTried.replacingOccurrences(of: "not tried: ", with: "")))")
    }
    return (mark, suffix, lines)
}
/// A tried way's line: ✓, ⚠ or ✗ over the window states tested (✓ or ✗ by
/// its only run when there were none), `worked` or `failed` saying how it went.
func triedWay(_ key: String, _ title: String, _ result: TrialResult, worked: String, failed: String) {
    if let summary = stateSummary(key) {
        way(summary.mark, "\(title): " + (summary.mark == "✗" ? failed : worked) + summary.suffix)
        summary.lines.forEach { say($0) }
    } else {
        way(result == .worked ? "✓" : "✗", "\(title): " + (result == .worked ? worked : failed))
        if let windowStatesNote { say("      – window states: not tested (\(windowStatesNote))") }
    }
}
if let script = scriptControls() {
    let fits = scripting?.fitsScriptablePlayer == true
    let kind = fits ? ", as Spotify and Apple Music"
        : " (\(scripting?.playsDocuments == true ? "on its documents, " : "")its own kind, as VLC: not the way ScriptablePlayers expects)"
    if let scriptResult {
        triedWay("script", "AppleScript", scriptResult, worked: "'\(script.pause)' and '\(script.play)' paused and played it\(kind)",
                 failed: scriptResult == .pausedOnly ? "'\(script.pause)' paused it, but '\(script.play)' didn't play it again"
                                                     : scriptProblem ?? "'\(script.pause)' didn't pause it")
    } else if let scriptProblem {
        way("✗", "AppleScript: \(scriptProblem)")
    } else if fits {
        way("?", "AppleScript: pause, play and its state, as Spotify and Apple Music (\(notTried))")
    } else {
        way("?", "AppleScript: play or pause commands, but not as Spotify's (a player type of its own, as VLC) (\(notTried))")
    }
} else {
    way("✗", "AppleScript: " + (scripting == nil ? "no scripting dictionary" : "a dictionary without play or pause"))
}
/// A trial's line: ✓ paused and played again, ✗ it only paused or didn't.
func resultLine(_ key: String, _ title: String, _ result: TrialResult, problem: String? = nil) {
    triedWay(key, title, result, worked: "pressing it paused and played it",
             failed: problem ?? (result == .pausedOnly ? "it paused, but didn't play again" : "pressing it changed nothing"))
}
if running == nil {
    way("–", "Playback menu: not checked (it isn't running)")
} else if !AXIsProcessTrusted() {
    way("–", "Playback menu: not checked (no Accessibility permission)")
} else if let menu {
    let found = "Playback menu '\(menu.title)'" + (menu.asAutoHushFindsIt ? "" : " (found by \(menu.arrows), not ⌘← ⌘→)")
    if let menuResult {
        resultLine("menu", found, menuResult)
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
            resultLine("page", found, pageResult)
        } else {
            way("?", "\(found) (\(notTried))")
        }
    } else {
        way("✗", "\(kind): " + (page.buttons == 0 ? "no page showed" : "none in sight named Play or Pause"))
    }
}
if let panelResult, canBeNowPlaying {
    triedWay("panel", "Now Playing panel", panelResult, worked: "pressing its row ('\(panelRowText ?? "")') paused and played it",
             failed: panelProblem ?? (panelResult == .pausedOnly ? "it paused, but didn't play again" : "pressing its row changed nothing"))
} else if running == nil {
    way("–", "Now Playing panel: not checked (it isn't running)")
} else if !canBeNowPlaying {
    way("✗", "Now Playing panel: \(panelNotNowPlaying)")
} else if !AXIsProcessTrusted() {
    way("–", "Now Playing panel: not checked (no Accessibility permission)")
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
        if let results = stateResults["page"], let summary = stateSummary("page"), summary.mark == "⚠" {
            let worked = results.filter { $0.result == .worked }.map(\.state.title)
            let failed = results.filter { $0.result != .worked }.map(\.state.title)
            say("  It works with its window " + worked.joined(separator: ", ") + "; not " + failed.joined(separator: ", ") + ".")
            if launchedWithOption == false, results.contains(where: { $0.result != .worked && [.covered, .otherDesktop, .otherDesktopCovered, .fullScreen].contains($0.state) }) {
                say("  Opened with \(LaunchOption.occludedWindows), Chromium keeps its page taking presses while its window is covered")
                say("  or on another desktop: relaunch it with it (the Player Check app's Relaunch) and check again.")
            }
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
