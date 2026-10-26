import AppKit
import AutoHushKit
import CheckedPlayers
import PlayerCheckKit
import ScriptablePlayers
import WebAppPlayers

// MARK: - What to do, and to which app

/// What a test runs the tool with, set before anything reads `arguments`:
/// the test runner's own command line names no app, and the tool would end.
nonisolated(unsafe) var argumentsForTests: [String]?
/// The run's command line, without the tool's own path.
let arguments = argumentsForTests ?? Array(CommandLine.arguments.dropFirst())

/// What --play and --pause do.
typealias Action = CommandLineOptions.Action

/// The ways to control an app, as --via names them, in the order a check tries them.
typealias Way = CheckResult.WayKind

/// The value after `option`, if it's given.
func value(of option: String) -> String? { CommandLineOptions.value(of: option, in: arguments) }

/// The app: the argument that's neither an option nor an option's value, wherever it comes.
let target: String = {
    guard let app = CommandLineOptions.app(in: arguments) else {
        fail("usage: playercheck <app name, bundle ID or path> [--block-input | --read-only | --play | --pause [--via script|menu|page|panel]] [--developer]")
    }
    return app
}()

/// --read-only: the checks without the test.
let readOnly = arguments.contains(CommandLineOptions.readOnly)
/// --play or --pause: does just that, by `via`, else by the first way that
/// works: AppleScript, the page's button, the menu.
let action: Action? = Action.allCases.first { arguments.contains($0.option) }
/// --via's way.
let via: Way? = {
    guard let index = arguments.firstIndex(of: CommandLineOptions.via) else { return nil }
    guard index + 1 < arguments.count, let way = Way(rawValue: arguments[index + 1]) else {
        fail("--via takes one of: " + Way.allCases.map(\.rawValue).joined(separator: ", "))
    }
    return way
}()
/// The test: each way to control it is tried, pausing it and playing it again.
let testing = !readOnly && action == nil
/// --result <file>: where a check writes what it found, for AutoHush's Add
/// an App… (`CheckResult`, as JSON), once it's done.
let resultFile = value(of: CommandLineOptions.result).map { URL(fileURLWithPath: $0) }
/// --logs <folder>: where the run's log goes, instead of ~/Library/Logs/PlayerCheck
/// (AutoHush keeps its checks' with its own log).
let logsFolder = value(of: CommandLineOptions.logs).map { URL(fileURLWithPath: $0, isDirectory: true) }
/// --caches <folder>: where what's kept between runs goes (the page buttons
/// found and learned, the apps' own words), instead of ~/Library/Caches/PlayerCheck
/// (AutoHush keeps its checks' in its own caches folder).
let cachesFolder = value(of: CommandLineOptions.caches).map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/PlayerCheck", isDirectory: true)
/// --partial: a test goes on without Audio Recording (the app isn't muted,
/// whether it plays is told by other signs) or Automation (its AppleScript
/// isn't tried); only Accessibility is needed. AutoHush's Add an App… says
/// what's missing first, and passes it whether anything is missing or not.
let partial = arguments.contains(CommandLineOptions.partial)
/// --no-taps: AntiDot mode's promise, no audio taps at all: its level isn't
/// measured and it isn't muted during the test, as without Audio Recording
/// (whether it plays is told by other signs), and Audio Recording isn't needed.
let noTaps = arguments.contains(CommandLineOptions.noTaps)
/// --block-input: while the test moves the window and presses, whoever runs
/// it can't click, scroll or type (`InputBlock`). AutoHush and the Player
/// Check app pass it; a shell has no panel to stop from, and Ctrl-C would be blocked.
let blockInput = testing && arguments.contains(CommandLineOptions.blockInput)
/// --developer: the report's lines for whoever adds a player to the code
/// too (`forDevelopers`).
let developer = arguments.contains(CommandLineOptions.developer)
/// --play or --pause by one way: only what that way needs is read, and what
/// shows whether the app plays (`isPlaying`), so a press starts sooner.
let pressingOneWay = action != nil && via != nil

/// The app's bundle: a path, a bundle ID, or a name in the Applications folders.
func findApp(_ target: String) -> URL? {
    // A path only when it looks like one: an app's name may also be a
    // folder's here (the home folder has some named so).
    if target.contains("/") || target.hasSuffix(".app"), FileManager.default.fileExists(atPath: target) {
        return URL(fileURLWithPath: target)
    }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) { return url }
    let name = target.hasSuffix(".app") ? target : target + ".app"
    let folders = ApplicationFolders.all.map(\.path)
        + [ApplicationFolders.system, ApplicationFolders.applications].map { $0.appending(path: "Utilities").path }
    for folder in folders where FileManager.default.fileExists(atPath: folder + "/" + name) {
        return URL(fileURLWithPath: folder + "/" + name)
    }
    return NSWorkspace.shared.runningApplications.first { $0.localizedName == target }?.bundleURL
}

/// The app checked or pressed, as its bundle names it.
struct CheckedApp: Sendable {
    let url: URL
    let bundleID: String
    let name: String
    let version: String

    static let found: CheckedApp = {
        guard let url = findApp(target), let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            fail("no app found for \(target)")
        }
        let info = bundle.infoDictionary ?? [:]
        return CheckedApp(url: url, bundleID: id, name: AppName.of(appAt: url),
                          version: info["CFBundleShortVersionString"] as? String ?? "?")
    }()
}
var appURL: URL { CheckedApp.found.url }
var bundleID: String { CheckedApp.found.bundleID }
var appName: String { CheckedApp.found.name }
var isWebApp: Bool { bundleID.hasPrefix(SafariWebApp.bundleIDPrefix) }

/// The app's process, when it runs.
@MainActor var running = NSRunningApplication.running(bundleID)

/// The app in front when the run started: the one a test comes back to
/// when it wasn't run from an app (a shell), as by then whoever started the
/// app playing may have brought it forward.
@MainActor var frontAtStart: NSRunningApplication?

/// Opens this run's log and says which app it is.
@MainActor func startRun() {
    frontAtStart = WindowStates.frontPID().flatMap { NSRunningApplication(processIdentifier: $0) }
    runLog.start(app: appName, doing: RunLogName.doing(action, via: via, readOnly: readOnly))
    say("\(appName) \(CheckedApp.found.version) (\(bundleID))")
    say("  \(appURL.path)")
    say("  " + (running.map { "running, pid \($0.processIdentifier)" } ?? "not running: the menu, sound and Now Playing checks need it running"))
    changes.appPID = running?.processIdentifier ?? 0
}

/// Whether something besides its menu's or page's word shows whether it
/// plays: its scripted state, or what it reports to Now Playing, which only
/// an administrator can read.
@MainActor var hasOtherSign: Bool { scripting?.hasState == true || (canBeNowPlaying && isAdministrator) }

/// A press by one way reads the menu and the page for their own way (the
/// panel needs the page's player bar, which names the song), or when nothing
/// else shows whether the app plays.
@MainActor func pressNeeds(_ ways: Set<Way>) -> Bool { !pressingOneWay || via.map(ways.contains) == true || !hasOtherSign }
