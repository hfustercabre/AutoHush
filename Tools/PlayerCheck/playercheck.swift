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
//                                                      just plays or pauses it, by that way or the first that works
//   playercheck --now-playing-list [hours]             the apps macOS keeps in Now Playing, from its log
//                                                      (administrators only): "<bundle ID>\t<pid>\t<state>\t<1 if active>\t<name>",
//                                                      then "#active\t<pid>"
//   playercheck --now-playing-list --since <unix time> what changed since then, apps gone as "Removed"
//   playercheck --now-playing-reasons <app path>…      why each app can be in Now Playing: "<path>\t<reason>"
//                                                      (empty when nothing shows it can), as Player Check lists them
// Build: swiftc -O -o playercheck playercheck.swift
import AppKit
import ApplicationServices
import CoreAudio
import OSLog

// MARK: - Output

/// Set for --play and --pause: the checks run silently, then one line says what was done.
var quiet = false
func say(_ line: String = "") {
    guard !quiet else { return }
    print(line)
    fflush(stdout)
}
func fail(_ line: String) -> Never { FileHandle.standardError.write(Data("playercheck: \(line)\n".utf8)); exit(1) }
// Whoever reads the output may go first (Player Check quitting mid-check):
// writing then fails quietly, and a test that paused the app still plays
// it again and puts back what it changed, instead of being killed.
signal(SIGPIPE, SIG_IGN)

// MARK: - Now Playing (MediaRemote, read only)

/// The process in Now Playing, 0 for none, -1 when MediaRemote doesn't
/// answer. A process asks MediaRemote once and keeps its first answer, so
/// each question runs a fresh copy of this tool (`--now-playing-pid`).
func nowPlayingPID() -> pid_t {
    let child = Process()
    // This file's own path: inside the Player Check app, Bundle.main is the app's.
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    child.executableURL = URL(fileURLWithPath: proc_pidpath(getpid(), &path, UInt32(path.count)) > 0
                              ? String(cString: path) : CommandLine.arguments[0])
    child.arguments = ["--now-playing-pid"]
    let output = Pipe()
    child.standardOutput = output
    guard (try? child.run()) != nil else { return -1 }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    child.waitUntilExit()
    return pid_t(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
}

func printNowPlayingPID() -> Never {
    typealias Ref = UnsafeRawPointer
    guard let mediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
          let origin = dlsym(mediaRemote, "MRMediaRemoteGetLocalOrigin"),
          let create = dlsym(mediaRemote, "MRNowPlayingPlayerPathCreate"),
          let resolve = dlsym(mediaRemote, "MRMediaRemoteNowPlayingResolvePlayerPath"),
          let client = dlsym(mediaRemote, "MRNowPlayingPlayerPathGetClient"),
          let clientPID = dlsym(mediaRemote, "MRNowPlayingClientGetProcessIdentifier")
    else { print(-1); exit(0) }
    let localOrigin = unsafeBitCast(origin, to: (@convention(c) () -> Ref?).self)
    let createPath = unsafeBitCast(create, to: (@convention(c) (Ref?, Ref?, Ref?) -> Ref?).self)
    let resolvePath = unsafeBitCast(resolve, to: (@convention(c) (Ref?, Ref, @escaping @convention(block) (Ref?, Ref?) -> Void) -> Void).self)
    let pathClient = unsafeBitCast(client, to: (@convention(c) (Ref?) -> Ref?).self)
    let pidOfClient = unsafeBitCast(clientPID, to: (@convention(c) (Ref?) -> Int32).self)
    resolvePath(createPath(localOrigin(), nil, nil), UnsafeRawPointer(Unmanaged.passUnretained(DispatchQueue.main).toOpaque())) { resolved, error in
        print(error == nil ? (pathClient(resolved).map(pidOfClient) ?? 0) : -1)
        exit(0)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { print(-1); exit(0) }
    RunLoop.main.run()
    exit(0)
}

if CommandLine.arguments.dropFirst().first == "--now-playing-pid" { printNowPlayingPID() }

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
/// line per app, "<path>\t<why it can be in Now Playing, or nothing>".
if CommandLine.arguments.dropFirst().first == "--now-playing-reasons" {
    for path in CommandLine.arguments.dropFirst(2) {
        let url = URL(fileURLWithPath: path)
        print(path + "\t" + (nowPlayingReason(of: url, bundleID: Bundle(url: url)?.bundleIdentifier) ?? ""))
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
    var properties: [String: String] = [:]
    var enumerators: Set<String> = []

    var suite: String? {
        let pauses = Set(commands.keys.filter { $0.hasSuffix("Paus") }.map { String($0.prefix(4)) })
        let plays = Set(commands.keys.filter { $0.hasSuffix("Play") }.map { String($0.prefix(4)) })
        return pauses.intersection(plays).sorted().first
    }
    var hasPlayerState: Bool { properties["pPlS"] != nil }
    /// A true/false `playing` property instead (VLC's): its state too.
    var hasPlayingFlag: Bool { properties.values.contains("playing") }
    var hasStateValues: Bool { enumerators.isSuperset(of: ["kPSS", "kPSP", "kPSp"]) }
    var hasVolume: Bool { properties["pVol"] != nil }
    /// A `current track` (pTrk) with a name: what it plays, by script.
    var hasCurrentTrack: Bool { properties["pTrk"] != nil }
    var fitsScriptablePlayer: Bool { suite != nil && hasPlayerState && hasStateValues }
}

/// The app's dictionary, as `sdef` prints it (from an .sdef, an aete or a
/// script suite alike); `nil` when it has none.
func readScripting(_ url: URL) -> Scripting? {
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
    var scripting = Scripting()
    func attributes(_ xpath: String) -> [(code: String, name: String)] {
        ((try? document.nodes(forXPath: xpath)) ?? []).compactMap { node in
            guard let element = node as? XMLElement, let code = element.attribute(forName: "code")?.stringValue else { return nil }
            return (code, element.attribute(forName: "name")?.stringValue ?? "")
        }
    }
    for (code, name) in attributes("//command") { scripting.commands[code] = name }
    for (code, name) in attributes("//property") { scripting.properties[code] = name }
    scripting.enumerators = Set(attributes("//enumerator").map(\.code))
    return scripting.commands.isEmpty && scripting.properties.isEmpty ? nil : scripting
}

say()
say("Scripting dictionary")
let scripting = readScripting(appURL)
if let scripting {
    let playLike = scripting.commands.filter { ["play", "pause", "playpause", "stop"].contains($0.value.lowercased()) }
    say("  commands: " + (playLike.isEmpty ? "no play or pause" : playLike.sorted { $0.key < $1.key }.map { "\($0.value) (\($0.key))" }.joined(separator: ", ")))
    say("  player state (pPlS): \(scripting.hasPlayerState ? "yes" : "no")"
        + (scripting.hasPlayerState ? ", values stopped/playing/paused: \(scripting.hasStateValues ? "yes" : "no")" : ""))
    say("  sound volume (pVol): \(scripting.hasVolume ? "yes, so it can fade" : "no, so no fades")")
    if let suite = scripting.suite { say("  pause and play share suite '\(suite)'") }
} else {
    say("  none: it can't be scripted")
}

// MARK: - Playback menu (Accessibility, as AutoHush's AccessibilityPlaybackMenu)

extension AXUIElement {
    func value(_ attribute: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success ? value : nil
    }
    var children: [AXUIElement] { value(kAXChildrenAttribute) as? [AXUIElement] ?? [] }
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

/// The undocumented HIServices function `_AXUIElementCreateWithRemoteToken`,
/// as AutoHush uses it (AccessibilityWindows): an app's windows on every
/// desktop, where `kAXWindowsAttribute` lists only those on the current one.
/// Nil if a macOS update removes it.
typealias RemoteTokenFunction = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
let remoteToken: RemoteTokenFunction? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken")
    .map { unsafeBitCast($0, to: RemoteTokenFunction.self) }

/// The windows last found on other desktops: the search takes about 70 ms
/// (up to 1 s), and pages are read every quarter second, so they're kept
/// for 10 s while each still answers as a window.
var otherDesktopWindows: (pid: pid_t, windows: [AXUIElement], found: Date)?

/// The app's windows on this desktop, else, as AutoHush finds them, on
/// any other (`onThisDesktop` false: not on screen, so nothing there can be
/// hit-tested). A token names one element of a process: its pid, 0, the
/// magic number "coco" and the element's number; its windows have low
/// numbers, so the first 1000 are tried (about 70 ms), for 1 s at most.
func appWindows(of pid: pid_t) -> (windows: [AXUIElement], onThisDesktop: Bool) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    let shown = app.value(kAXWindowsAttribute) as? [AXUIElement] ?? []
    guard shown.isEmpty, let remoteToken else { return (shown, true) }
    if let kept = otherDesktopWindows, kept.pid == pid, Date().timeIntervalSince(kept.found) < 10,
       !kept.windows.isEmpty, kept.windows.allSatisfy({ $0.text(kAXRoleAttribute) == kAXWindowRole }) {
        return (kept.windows, false)
    }
    let deadline = Date().addingTimeInterval(1)
    var token = Data(count: 20)
    token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
    token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) })
    var found: [AXUIElement] = []
    for number in UInt64(0)..<1000 where Date() < deadline {
        token.replaceSubrange(12..<20, with: withUnsafeBytes(of: number) { Data($0) })
        guard let element = remoteToken(token as CFData)?.takeRetainedValue() else { continue }
        AXUIElementSetMessagingTimeout(element, 0.3)
        if element.text(kAXRoleAttribute) == kAXWindowRole { found.append(element) }
    }
    otherDesktopWindows = (pid, found, Date())
    return (found, false)
}

struct PlaybackMenu {
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
func playbackMenu(pid: pid_t) -> PlaybackMenu? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    guard let bar = app.value(kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
    let menuBar = bar as! AXUIElement
    var other: PlaybackMenu?
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
            return PlaybackMenu(title: barItem.title, toggle: first, asAutoHushFindsIt: true, arrows: "⌘← ⌘→")
        }
        if other == nil, first.value(kAXMenuItemCmdVirtualKeyAttribute) as? Int == 49 {
            other = PlaybackMenu(title: barItem.title, toggle: first, asAutoHushFindsIt: false,
                                 arrows: "\(modifierSymbols(left[0]))← \(modifierSymbols(right[0]))→")
        }
    }
    return other
}

/// The symbols of AXMenuItemCmdModifiers: ⇧ 1, ⌥ 2, ⌃ 4, and 8 for no ⌘.
func modifierSymbols(_ modifiers: Int) -> String {
    (modifiers & 4 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "") + (modifiers & 1 != 0 ? "⇧" : "")
        + (modifiers & 8 != 0 ? "" : "⌘")
}

say()
say("Playback menu")
var menu: PlaybackMenu?
if running == nil {
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
} else {
    say("  none: no menu with ⌘← and ⌘→, nor one with its first item on Space and other arrows")
}

// MARK: - Sound

typealias Responsible = @convention(c) (pid_t) -> pid_t
let responsible = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")!,
                                to: Responsible.self)

func audioProperty<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    return value
}

func audioBundleID(_ object: AudioObjectID) -> String {
    var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return "" }
    return value.takeRetainedValue() as String
}

/// An app's name, else its executable's.
func processName(_ pid: pid_t) -> String {
    if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return "pid \(pid)" }
    return URL(fileURLWithPath: String(cString: path)).lastPathComponent
}

/// The processes with sound output running that macOS holds the app
/// responsible for (its own, or helpers such as a web app's WebKit process),
/// as "name (bundle ID, pid)".
func soundProcesses(of pid: pid_t) -> [String] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
    var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects)
    return objects.compactMap { object in
        guard audioProperty(object, kAudioProcessPropertyIsRunningOutput, UInt32(0)) != 0 else { return nil }
        let processPID = audioProperty(object, kAudioProcessPropertyPID, pid_t(0))
        guard processPID == pid || responsible(processPID) == pid else { return nil }
        let id = audioBundleID(object)
        return "\(processName(processPID)) (\(id.isEmpty ? "no bundle ID" : id), pid \(processPID))"
    }.sorted()
}

say()
say("Sound and Now Playing")
if let running {
    let sound = soundProcesses(of: running.processIdentifier)
    say("  sound output running now: " + (sound.isEmpty ? "none (it isn't playing)" : sound.joined(separator: "; ")))
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
let manualAccessibility = "AXManualAccessibility"
let enhancedUserInterface = "AXEnhancedUserInterface"
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
}
let hiddenInterface: HiddenInterface? = {
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
}()
var isFlutter: Bool { if case .flutter? = hiddenInterface { true } else { false } }

/// Play and Pause as players' pages name their buttons (any case), in
/// English, Spanish, Catalan and a few more: what this tool looks for and
/// presses. AutoHush itself learns the button by its words changing, in any
/// language.
let playWords: Set<String> = ["play", "reproducir", "reprodueix", "reproduir", "lecture", "lire", "wiedergabe",
                              "abspielen", "riproduci", "reproduzir"]
let pauseWords: Set<String> = ["pause", "pausa", "pausar", "posa en pausa", "mettre en pause", "pausieren"]
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
struct PageButton {
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
func pageButtons(pid: pid_t) -> [PageButton]? {
    let (windows, onThisDesktop) = appWindows(of: pid)
    guard !windows.isEmpty else { return nil }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    let hidden = app.value(kAXHiddenAttribute) as? Bool == true
    let search: [String: Any] = ["AXSearchKey": "AXButtonSearchKey", "AXResultsLimit": 2000, "AXDirection": "AXDirectionNext",
                                 "AXVisibleOnly": false, "AXImmediateDescendantsOnly": false]
    return windows.flatMap { window -> [PageButton] in
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
            return PageButton(element: element, label: label(of: element),
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
/// the window, lower than the bar's own button, but covered. Chromium
/// answers a hit test from its last one at first, then precisely a moment
/// later (Spotify's bar button behind other windows: a group elsewhere,
/// then the button), so a miss is asked again.
func isUncovered(_ button: PageButton, pid: pid_t) -> Bool {
    // Off screen (another desktop, hidden, minimised): whatever is there would answer.
    guard button.onScreen else { return true }
    guard let frame = button.element.frame else { return false }
    let app = AXUIElementCreateApplication(pid)
    for attempt in 0..<2 {
        if attempt > 0 { Thread.sleep(forTimeInterval: 0.2) }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(frame.midX), Float(frame.midY), &hit) == .success,
              var node = hit else { return true } // can't tell: keep it
        for _ in 0..<8 {
            if CFEqual(node, button.element) { return true }
            guard let parent = node.value(kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            node = parent as! AXUIElement
        }
    }
    return false
}

/// The player's button named one of `words` (any case, alone or first),
/// ranked as AutoHush's learning ranks them: of those in sight and not
/// covered, the lowest with a player's slider or progress bar around it,
/// else the lowest (players keep their controls at the bottom).
func playerButton(pid: pid_t, named words: Set<String>) -> (button: PageButton, withControls: Bool)? {
    let candidates = (pageButtons(pid: pid) ?? [])
        .filter { $0.inSight && named($0.label, words) }
        .sorted { ($0.fromBottom ?? .infinity) < ($1.fromBottom ?? .infinity) }
    // Hit tests and slider searches only until the player's button is found.
    var lowest: PageButton?
    for candidate in candidates where isUncovered(candidate, pid: pid) {
        if playerBar(of: candidate.element) != nil { return (candidate, true) }
        if lowest == nil { lowest = candidate }
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
    let toggle: PageButton?
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
/// Turns a switch on; whether the app took it. One this tool turned on is
/// turned back off at the end, unless it may have been on before: VoiceOver's
/// reads back, so one already on is left alone; Electron's reads back off
/// even while it's on (Deezer), so with the page readable already (someone
/// may have it on) it's left on.
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
    if attribute == manualAccessibility, pageReadable {
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
/// the switch went on again in front. So when nothing shows, the app comes
/// forward a moment with the switch turned off and on again, then the app
/// that was in front.
func showPage(with attribute: String, pid: pid_t, count: inout Int, shownAfter: inout TimeInterval?) -> Bool? {
    guard turnOn(attribute, pid: pid, pageReadable: false) else { return nil }
    var waited = waitForPage(pid, seconds: 4)
    var seconds = 4
    if waited.count == 0 {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.processIdentifier != pid { stopState.frontToRestore = front.bundleURL }
        bringForward(appURL)
        broughtForward = true
        if stopState.switchesOn.contains(attribute) {
            _ = setSwitch(attribute, false, pid: pid)
            _ = setSwitch(attribute, true, pid: pid)
        }
        waited = waitForPage(pid, seconds: 6)
        seconds += 6
        if let url = stopState.frontToRestore {
            bringForward(url)
            stopState.frontToRestore = nil
            // Its desktop slides away for about half a second, and the
            // frames read meanwhile are off (Spotify's Play: not in sight).
            Thread.sleep(forTimeInterval: 1)
        }
        say("  its window was out of sight: brought it forward a moment, with the switch turned on again there"
            + " (Chromium and Flutter apps may build their \(isFlutter ? "interface" : "page") only while their window can be seen)")
    }
    guard waited.count > 0 else {
        say("  \(switchName(attribute)) (\(attribute)) on, but nothing showed in \(seconds) s")
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

if running == nil {
    say("  not checked: the app isn't running")
    pageNotChecked = "it isn't running"
} else if !AXIsProcessTrusted() {
    say("  not checked: this tool (or the app running it) needs the Accessibility permission")
    pageNotChecked = "no Accessibility permission"
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
        if count > 0, let hidden = hiddenInterface {
            // Shown to an assistive tool before (VoiceOver, or this tool):
            // a switch still goes on, so the app keeps the page up to date.
            say("  readable already: an assistive tool asked for it before")
            pageSwitch = hidden.switches.first { turnOn($0, pid: pid, pageReadable: true) }
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
            let readStart = Date()
            let buttons = pageButtons(pid: pid) ?? []
            let readTime = Date().timeIntervalSince(readStart)
            let toggle = playerButton(pid: pid, named: playPauseWords)
            page = PageCheck(buttons: buttons.count, toggle: toggle?.button, withControls: toggle?.withControls ?? false)
            if toggle?.withControls == true { barToggle = toggle?.button.element }
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

// MARK: - Press test

/// Why AppleScript can't be used, when macOS refuses it (no Automation permission).
var scriptProblem: String?

/// -1743: macOS refused the Apple event (the Automation permission).
func noteScriptError(_ number: Any?) {
    if (number as? Int) == -1743 {
        scriptProblem = "macOS doesn't let this tool (or the app running it) control \(appName) by AppleScript: allow it in System Settings → Privacy & Security → Automation"
    }
}

/// The app's state by script, when its dictionary has it and it answers:
/// its `player state` (stopped, playing, paused, as Spotify's), else its
/// `playing` flag (VLC's: playing or paused). Only macOS refusing it (-1743:
/// no Automation permission for whatever runs this tool) stops the asking;
/// another error (a timeout, -1712, from a busy VLC) counts for that look
/// only. Each kind of error is said once.
var scriptError: Any?
var scriptErrorsSaid: Set<String> = []
func scriptedState() -> String? {
    guard let scripting, scripting.hasPlayerState || scripting.hasPlayingFlag, scriptError == nil else { return nil }
    let question = scripting.hasPlayerState ? "get player state as string" : "get playing"
    var error: NSDictionary?
    let result = NSAppleScript(source: "tell application id \"\(bundleID)\" to \(question)")?.executeAndReturnError(&error)
    if let error {
        let number = error[NSAppleScript.errorNumber] ?? "?"
        noteScriptError(number)
        let refused = (number as? Int) == -1743
        if refused { scriptError = number }
        if scriptErrorsSaid.insert("\(number)").inserted {
            say("  its state can't be read by script: error \(number)" + (refused ? "" : " (asked again at the next look)"))
        }
        return nil
    }
    guard let result else { return nil }
    return scripting.hasPlayerState ? result.stringValue : (result.booleanValue ? "playing" : "paused")
}

/// The name of what it plays, by script, when its dictionary has a
/// `current track` (Spotify's, Music's, TV's). It stays while paused, where
/// a window's title may not (a paused Spotify's says "Spotify Premium").
/// Nil without one, or when it doesn't answer (nothing loaded).
func scriptedSong() -> String? {
    guard let scripting, scripting.hasCurrentTrack, scriptError == nil else { return nil }
    var error: NSDictionary?
    let result = NSAppleScript(source: "tell application id \"\(bundleID)\" to get name of current track")?.executeAndReturnError(&error)
    if let error {
        noteScriptError(error[NSAppleScript.errorNumber])
        return nil
    }
    return result?.stringValue
}

/// Sends an AppleScript command to the app; false (and why) when it fails.
func sendScript(_ command: String) -> Bool {
    var error: NSDictionary?
    _ = NSAppleScript(source: "tell application id \"\(bundleID)\" to \(command)")?.executeAndReturnError(&error)
    if let error {
        noteScriptError(error[NSAppleScript.errorNumber])
        say("    \(command): error \(error[NSAppleScript.errorNumber] ?? "?")")
    }
    return error == nil
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

/// The state notifications seen during the test, with their userInfo keys.
final class NotificationLog: NSObject {
    var seen: [String: Set<String>] = [:]
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
    }
}

/// The page's Play/Pause in its player bar, found last (`barToggle`): read
/// again by its words alone, as a full search reads the whole page and
/// hit-tests its buttons. A song's own button (no player bar around it)
/// isn't kept: a bar may show up once something plays. Without one, the
/// full search runs at most every 2 s.
func pageToggleLabel(_ pid: pid_t) -> String? {
    if let element = barToggle {
        let words = label(of: element)
        if named(words, playPauseWords) { return words }
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
/// and its sound output.
struct Look: Equatable {
    var menuTitle: String?
    var state: String?
    var reported: String?
    var pageToggle: String?
    var sounding: Bool
    var line: String {
        [menuTitle.map { "menu '\($0)'" }, state.map { "state \($0)" }, reported.map { "reports \($0.lowercased())" },
         pageToggle.map { "page '\($0)'" }, "sound \(sounding ? "on" : "off")"]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

func look(_ pid: pid_t) -> Look {
    // The log is read only for an app with no scripted state (its own is surer).
    let state = scriptedState()
    return Look(menuTitle: menu == nil ? nil : playbackMenu(pid: pid)?.toggleTitle, state: state,
                reported: state == nil ? reportedState() : nil, pageToggle: page?.toggle == nil ? nil : pageToggleLabel(pid),
                sounding: !soundProcesses(of: pid).isEmpty)
}

/// Waits up to `seconds`, running the run loop (for notifications), until
/// `done` holds (or a stop is asked), then a second more for late
/// notifications; the last look.
func waitFor(_ seconds: Double, pid: pid_t, until done: (Look) -> Bool) -> Look {
    let deadline = Date().addingTimeInterval(seconds)
    var current = look(pid)
    while !done(current), Date() < deadline, !stopState.isRequested {
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        current = look(pid)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    return current
}

/// How a trial went: it paused and played again, it only paused, or it
/// didn't pause.
enum TrialResult { case worked, pausedOnly, didNotPause }

/// Whether a press took, judged by the surest sign the app had before it:
/// its scripted state, else what it reports to Now Playing, else its page's
/// button (Play while paused), else its menu's word or its sound. (Deezer's
/// menu word changes late by itself: it said Play while playing, then Pause
/// a second later, with nothing pressed.)
struct Sign {
    let before: Look
    var byState: Bool { before.state != nil }
    var byReport: Bool { !byState && before.reported != nil }
    var byPage: Bool { !byState && !byReport && before.pageToggle != nil }
    func paused(_ now: Look) -> Bool {
        if byState { return now.state != nil && now.state != "playing" }
        if byReport { return now.reported != nil && now.reported != "Playing" }
        if byPage { return now.pageToggle.map { named($0, playWords) } ?? false }
        return now.menuTitle != before.menuTitle || !now.sounding
    }
    func playing(_ now: Look) -> Bool {
        if byState { return now.state == "playing" }
        if byReport { return now.reported == "Playing" }
        if byPage { return now.pageToggle.map { named($0, pauseWords) } ?? false }
        return now.sounding
    }
}

/// Pauses with `pause`, sees whether it took (`Sign`), plays again with
/// `play` if it did; `undo` runs when it didn't (a press that may have hit
/// another app). A stop meanwhile waits until it plays again.
func trial(_ label: String, pid: pid_t, pause: () -> Bool, play: () -> Bool, undo: (() -> Void)? = nil) -> TrialResult {
    stopState.setInTrial(true)
    defer { stopState.setInTrial(false) }
    let before = look(pid)
    let sign = Sign(before: before)
    let paused = sign.paused, playing = sign.playing
    say("  \(label): before, \(before.line)")
    guard pause() else { say("    couldn't send it"); return .didNotPause }
    let after = waitFor(4, pid: pid, until: paused)
    guard paused(after) else {
        say("    after the pause: \(after.line) → it didn't pause in 4 s")
        undo?()
        return .didNotPause
    }
    say("    after the pause: \(after.line) → it paused")
    guard play() else {
        say("    couldn't play it again")
        return .pausedOnly
    }
    let back = waitFor(4, pid: pid, until: playing)
    let again = playing(back)
    say("    after playing again: \(back.line) → " + (again ? "it plays" : "it didn't play again in 4 s"))
    return again ? .worked : .pausedOnly
}

/// Whether it plays, as far as can be seen: its scripted state, else what
/// it reports to Now Playing, else its page's button (Pause while it plays),
/// else its sound (which an Electron app or a web app keeps a few seconds
/// after a pause).
func isPlaying(_ pid: pid_t) -> Bool {
    let now = look(pid)
    if let state = now.state { return state == "playing" }
    if let reported = now.reported { return reported == "Playing" }
    if let toggle = now.pageToggle { return named(toggle, pauseWords) }
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

/// The page's button to press to pause (or play): the player bar's button
/// with that word; else, when the app reports how it is, the bar's button
/// whatever its word, since it toggles (an Electron page on another desktop
/// keeps its word: Play while it plays); else one with that word.
func pageButtonToPress(pid: pid_t, pausing: Bool) -> PageButton? {
    let wanted = playerButton(pid: pid, named: pausing ? pauseWords : playWords)
    if let wanted, wanted.withControls { return wanted.button }
    if reportedState() != nil, let bar = playerButton(pid: pid, named: playPauseWords), bar.withControls { return bar.button }
    return wanted?.button
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
            }
            return going
        }
        if let script, scriptProblem == nil, ready() {
            // A toggle is sent for the pause only while it plays, and again to play.
            scriptResult = trial("by script (\(script.pause), \(script.play))", pid: pid,
                                 pause: { sendScript(script.pause) }, play: { sendScript(script.play) })
            stopIfRequested()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
        if menu != nil, ready() {
            func press() -> Bool {
                guard let item = playbackMenu(pid: pid)?.toggle else { return false }
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
            menuResult = trial("by its menu", pid: pid, pause: press, play: press)
            stopIfRequested()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
        if page?.toggle != nil, ready() {
            func pressPage(pausing: Bool) -> Bool {
                guard let button = pageButtonToPress(pid: pid, pausing: pausing) else {
                    say("    no button in sight to press"); return false
                }
                return AXUIElementPerformAction(button.element, kAXPressAction as CFString) == .success
            }
            pageResult = trial("by its page's button", pid: pid, pause: { pressPage(pausing: true) }, play: { pressPage(pausing: false) })
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
                                    })
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
    /// Waits up to 6 s for `done`, looking every quarter second.
    func within(_ done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(6)
        while !done() {
            guard Date() < deadline else { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
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
            guard sendScript(command) else {
                tried.append(scriptProblem ?? "AppleScript \(command) failed")
                continue
            }
            if within(isThere) {
                say("\(pausing ? "Paused" : "Played") it by AppleScript (\(command)).")
                finish(0)
            }
            tried.append("AppleScript \(command) sent, but it didn't change in 6 s")
        case "page":
            guard page?.toggle != nil else {
                tried.append("no Play/Pause button on its page")
                continue
            }
            // As it reports to Now Playing, else as its page's button says
            // (Pause while it plays, Play while it doesn't).
            let done = { isPlaying(pid) != pausing }
            if done() {
                say("It's \(pausing ? "paused" : "playing") already.")
                finish(0)
            }
            guard let button = pageButtonToPress(pid: pid, pausing: pausing),
                  AXUIElementPerformAction(button.element, kAXPressAction as CFString) == .success else {
                tried.append("couldn't press its page's \(pausing ? "Pause" : "Play")")
                continue
            }
            if within(done) {
                say("\(pausing ? "Paused" : "Played") it with its page's '\(button.label)' button"
                    + (pageSwitch.map { ", \(switchName($0)) on" } ?? "")
                    + (broughtForward ? " (brought forward a moment: Chromium and Flutter apps may build it only while their window can be seen)." : "."))
                finish(0)
            }
            tried.append("pressed its page's '\(button.label)', but it didn't change in 6 s")
        case "menu":
            guard let menu else {
                tried.append("no playback menu")
                continue
            }
            // Its first item toggles, so it's pressed only when it's the
            // other way; judged as a test judges it (`Sign`): its menu's word
            // counts only for an app with no surer sign, as Deezer's changes
            // late by itself.
            let before = look(pid)
            let sign = Sign(before: before)
            let done = { (now: Look) in pausing ? sign.paused(now) : sign.playing(now) }
            if done(before) {
                say("It's \(pausing ? "paused" : "playing") already.")
                finish(0)
            }
            let word = before.menuTitle ?? ""
            guard let item = playbackMenu(pid: pid)?.toggle,
                  AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
                tried.append("couldn't press its menu's first item")
                continue
            }
            if within({ done(look(pid)) }) {
                say("\(pausing ? "Paused" : "Played") it with its '\(menu.title)' menu's '\(word)'.")
                finish(0)
            }
            tried.append("pressed its menu's '\(word)', but nothing changed in 6 s")
        case "panel":
            if isPlaying(pid) != pausing {
                say("It's \(pausing ? "paused" : "playing") already.")
                finish(0)
            }
            guard pressInPanel(pid: pid, pausing: pausing) else {
                tried.append(panelProblem ?? "couldn't press its row in the Now Playing panel")
                continue
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
    let kind = fits ? ", as Spotify and Apple Music" : " (its own kind, as VLC: not the way ScriptablePlayers expects)"
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
        let found = "\(kind): '\(toggle.label)'" + (page.withControls ? "" : ", but no player bar around it")
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
    if !stateNotes.isEmpty {
        say("  State notification: \(stateNotes.joined(separator: ", ")).")
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
    say("  Scriptable, but not the way ScriptablePlayers expects: a player type of its own, as VLC (VLCSupport).")
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
