import AppKit
import AutoHushKit
import OSLog
import PlayerCheckKit
import WebAppPlayers

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

/// A client as the list names it: as the log does, else its app's name
/// (a web app's, for WebKit's media process), else its bundle ID.
func displayName(of client: NowPlayingReports.Client) -> String {
    if !client.name.isEmpty { return client.name }
    let app = client.id.contains("/") ? NSRunningApplication.runningApplications(withBundleIdentifier: client.appID).first
                                      : NSRunningApplication(processIdentifier: client.pid)
    return app?.localizedName ?? client.appID
}

/// The apps macOS keeps in Now Playing, one tab-separated line each:
/// bundle ID, process, last state (or Registered: ready for Now Playing,
/// never said it plays), 1 for the active one (the Now Playing app), name.
/// Unentitled apps can't ask MediaRemote for that list (since macOS 15.4),
/// so it's read from what MediaRemote's daemon writes in macOS's log since
/// the Mac started (or the last `hours`), as AutoHush reads it
/// (`NowPlayingReports`): each client it creates, each one's
/// "PlaybackState changed from … to …" (also while another app is the
/// active one), and those it removes when they quit. Reading the log needs
/// an administrator; its wording is macOS's, not an API (checked on macOS 27).
func printNowPlayingList() -> Never {
    var boot = timeval()
    var size = MemoryLayout<timeval>.size
    sysctlbyname("kern.boottime", &boot, &size, nil, 0)
    let rest = Array(CommandLine.arguments.dropFirst(2))
    // --since: only what changed since then (a caller that read the whole list
    // before keeps it up to date this way, without reading days of log again).
    let since = CommandLineOptions.value(of: "--since", in: rest).flatMap(Double.init)
    let start = since.map { Date(timeIntervalSince1970: $0) }
        ?? CommandLineOptions.operands(in: rest).first.flatMap(Double.init).map { Date().addingTimeInterval(-$0 * 3600) }
        ?? Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    let store: OSLogStore
    do { store = try OSLogStore.local() } catch {
        print("can't read macOS's log: \(error.localizedDescription)")
        exit(1)
    }
    var clients: [pid_t: NowPlayingReports.Client] = [:]
    guard NowPlayingReports.read(store, from: start, into: &clients) else {
        print("can't read macOS's log from \(start)")
        exit(1)
    }
    let active = nowPlayingPID()
    // Still there: not removed, and its process still runs. With --since, the
    // ones gone meanwhile too, as Removed.
    for client in clients.values {
        let there = !client.removed && NowPlayingReports.stillRuns(client.pid)
        guard there || since != nil else { continue }
        print([client.appID, "\(client.pid)", there ? client.reported ?? "Registered" : "Removed", client.pid == active ? "1" : "0",
               displayName(of: client)].joined(separator: "\t"))
    }
    print("#active\t\(active)")
    exit(0)
}

/// --now-playing-reasons <app path>…: for Add an App…'s list and the Player
/// Check app's, a line per app, "<path>\t<why it can be in Now Playing, or
/// nothing>\t<the framework that hides its interface, or nothing>\t<the
/// switches a check turns on for it, in order>", so the window shows this
/// tool's own rule. The paths are the arguments that are no option (nor
/// --logs' or --caches' folder).
func printNowPlayingReasons() -> Never {
    for path in CommandLineOptions.operands(in: Array(CommandLine.arguments.dropFirst(2))) {
        let url = URL(fileURLWithPath: path)
        let hidden = HiddenInterface.of(url)
        print([path, NowPlayingReason.of(appAt: url, bundleID: Bundle(url: url)?.bundleIdentifier) ?? "", hidden?.name ?? "",
               hidden?.switches.map { switchName($0, of: hidden) }.joined(separator: ", else ") ?? ""].joined(separator: "\t"))
    }
    exit(0)
}

// MARK: - Whether it can report to Now Playing

/// Whether anything in it can report to Now Playing (so it may have a row
/// in the Now Playing panel, and report its state): it reads the load
/// commands of every binary in the app (`NowPlayingReason`).
let canBeNowPlaying = NowPlayingReason.of(appAt: appURL, bundleID: bundleID) != nil

/// Whether this account can read what apps report to Now Playing: macOS's
/// log opens only to administrators (the admin group).
var isAdministrator: Bool { NowPlayingReports.isAdministrator }

// MARK: - What it reports to Now Playing

/// What apps report to Now Playing, followed for this run as AutoHush follows
/// it for a checked player (`NowPlayingReports`): the past read once from
/// macOS's log, back to when the app opened, and what follows live from one
/// `log stream`, which ends with this tool (`stop`, at its exit or a stop).
let nowPlayingReports = NowPlayingReports(idleLimit: nil)

/// Set once its level heard it while its report said it wasn't playing:
/// an app may report only while it's the Now Playing app (one said
/// “Paused” for half an hour while it played, another app holding Now
/// Playing, 2026-10-15), and a report that stale counts no more in this run (sound
/// heard is surer than a report of a pause; silence isn't: a quiet passage).
/// AutoHush's checked players judge their reports so too.
@MainActor var reportIsStale = false

/// Its report says it isn't playing while it's heard: the report is stale
/// from then on (`reportIsStale`), said once.
@MainActor func noteHeard(against reported: String?) {
    guard !reportIsStale, let reported, NowPlayingReports.state(reported: reported) != .playing else { return }
    reportIsStale = true
    say("  its Now Playing report says “\(reported.lowercased())” while it's heard playing: taken as stale, its level is judged instead")
}

@MainActor var reportsFollowed = false

/// Whether the app plays as it reports to Now Playing, the surest sign
/// after its AppleScript state: it holds wherever its window is (an
/// Electron app's page on another desktop keeps the word it had, Play
/// while it played). Read back to when the app opened, an hour at
/// most. Nil for an app that can't report to Now Playing, when the log
/// can't be read (not an administrator), or while it reported nothing since
/// then: its latest report as the log says it ("Playing", "Paused"…), from
/// the newest of its processes still there (a web app's is WebKit's media
/// process); nil too once the stream ended.
@MainActor func reportedState() -> String? {
    guard canBeNowPlaying, isAdministrator, !reportIsStale, let running else { return nil }
    if !reportsFollowed {
        reportsFollowed = true
        nowPlayingReports.follow(since: max(running.launchDate ?? .distantPast, Date().addingTimeInterval(-3600)))
    }
    return nowPlayingReports.latest(of: bundleID)?.reported
}
