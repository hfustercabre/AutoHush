import AppKit
import AutoHushKit
import OSLog

// MARK: - Now Playing (MediaRemote, read only)

/// The process in Now Playing, 0 for none, -1 when MediaRemote doesn't
/// answer, as AutoHush asks it (`NowPlayingApp`): a process asks MediaRemote
/// once and keeps its first answer, so each question runs a fresh copy of
/// this tool (with `NowPlayingApp.argument`).
func nowPlayingPID() -> pid_t {
    // This tool's own path: inside the Player Check app, Bundle.main is the app's.
    let own = URL(fileURLWithPath: executablePath(of: getpid()) ?? CommandLine.arguments[0])
    switch NowPlayingApp.current(executable: own) {
    case .process(let pid): return pid
    case .none: return 0
    case .unknown: return -1
    }
}

/// Whether the app (or a helper that plays for it) is the Now Playing one;
/// else which app is (or that MediaRemote didn't answer).
func nowPlayingHolder(_ pid: pid_t) -> (isThisApp: Bool, other: String) {
    let holder = nowPlayingPID()
    let other = holder < 0 ? "MediaRemote didn't answer" : holder == 0 ? "no app is"
        : (NSRunningApplication(processIdentifier: responsible(holder))?.localizedName ?? "pid \(holder)") + " is"
    return (holder > 0 && (holder == pid || responsible(holder) == pid), other)
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

/// What a reported state says: Playing, Paused and Stopped as they are; any
/// other (Interrupted…) as not playing.
func playerState(reported: String) -> PlayerState {
    switch reported {
    case "Playing": .playing
    case "Stopped": .stopped
    default: .paused
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

/// Whether a process still runs (or runs as another user).
func stillRuns(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

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
        let there = !client.removed && stillRuns(client.pid)
        guard there || since != nil else { continue }
        print([client.appID, "\(client.pid)", there ? client.state ?? "Registered" : "Removed", client.pid == active ? "1" : "0",
               client.displayName].joined(separator: "\t"))
    }
    print("#active\t\(active)")
    exit(0)
}

/// --now-playing-reasons <app path>…: for the Player Check app's list, a
/// line per app, "<path>\t<why it can be in Now Playing, or nothing>\t<the
/// framework that hides its interface, or nothing>\t<the switches a check
/// turns on for it, in order>", so the window shows this tool's own rule.
func printNowPlayingReasons() -> Never {
    for path in CommandLine.arguments.dropFirst(2) {
        let url = URL(fileURLWithPath: path)
        let hidden = HiddenInterface.of(url)
        print([path, nowPlayingReason(of: url, bundleID: Bundle(url: url)?.bundleIdentifier) ?? "", hidden?.name ?? "",
               hidden?.switches.map(switchName).joined(separator: ", else ") ?? ""].joined(separator: "\t"))
    }
    exit(0)
}

// MARK: - Whether it can report to Now Playing

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
/// in the Now Playing panel, and report its state): it reads the load
/// commands of every binary in the app (`nowPlayingReason`).
let canBeNowPlaying = nowPlayingReason(of: appURL, bundleID: bundleID) != nil

/// Whether this account can read what apps report to Now Playing: macOS's
/// log opens only to administrators (the admin group).
let isAdministrator: Bool = {
    var groups = [gid_t](repeating: 0, count: 256)
    let count = getgroups(Int32(groups.count), &groups)
    // Unknown: taken as one, and opening the log tells.
    return count < 0 || groups.prefix(Int(count)).contains(80)
}()

// MARK: - What it reports to Now Playing

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
        changes.streamPID = stream.processIdentifier
        atexit { if changes.streamPID > 0 { kill(changes.streamPID, SIGTERM) } }
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
                .filter { $0.appID == appID && $0.state != nil && !$0.removed && stillRuns($0.pid) }
                .max { ($0.changed ?? .distantPast) < ($1.changed ?? .distantPast) }?.state
        }
    }
}

@MainActor var reportedTracker: ReportedState?
@MainActor var reportedTrackerMade = false

/// Whether the app plays as it reports to Now Playing, the surest sign
/// after its AppleScript state: it holds wherever its window is (an
/// Electron app's page on another desktop keeps the word it had, Play
/// while Deezer played). Read back to when the app opened, an hour at
/// most. Nil for an app that can't report to Now Playing, when the log
/// can't be read (not an administrator), or while it reported nothing since then.
@MainActor func reportedState() -> String? {
    guard canBeNowPlaying, isAdministrator, let running else { return nil }
    if !reportedTrackerMade {
        reportedTrackerMade = true
        reportedTracker = ReportedState(appID: bundleID, since: max(running.launchDate ?? .distantPast, Date().addingTimeInterval(-3600)))
    }
    return reportedTracker?.state
}
