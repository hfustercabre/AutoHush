import AppKit

// MARK: - What to do, and to which app

let arguments = Array(CommandLine.arguments.dropFirst())

/// What --play and --pause do.
enum Action: String { case play, pause }

/// The ways to control an app, as --via names them, in the order a check tries them.
enum Way: String, CaseIterable { case script, menu, page, panel }

/// The app: the argument that's neither an option nor --via's way, wherever it comes.
let target: String = {
    guard let index = arguments.indices.first(where: { !arguments[$0].hasPrefix("--") && ($0 == 0 || arguments[$0 - 1] != "--via") }) else {
        fail("usage: playercheck <app name, bundle ID or path> [--read-only | --play | --pause [--via script|menu|page|panel]]")
    }
    return arguments[index]
}()

/// --read-only: the checks without the test.
let readOnly = arguments.contains("--read-only")
/// --play or --pause: does just that, by `via`, else by the first way that
/// works: AppleScript, the page's button, the menu.
let action: Action? = arguments.contains("--play") ? .play : arguments.contains("--pause") ? .pause : nil
/// --via's way.
let via: Way? = {
    guard let index = arguments.firstIndex(of: "--via") else { return nil }
    guard index + 1 < arguments.count, let way = Way(rawValue: arguments[index + 1]) else {
        fail("--via takes one of: " + Way.allCases.map(\.rawValue).joined(separator: ", "))
    }
    return way
}()
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
        return CheckedApp(url: url, bundleID: id,
                          name: (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String ?? url.deletingPathExtension().lastPathComponent,
                          version: info["CFBundleShortVersionString"] as? String ?? "?")
    }()
}
var appURL: URL { CheckedApp.found.url }
var bundleID: String { CheckedApp.found.bundleID }
var appName: String { CheckedApp.found.name }
var isWebApp: Bool { bundleID.hasPrefix("com.apple.Safari.WebApp.") }

/// The app's process, when it runs.
@MainActor var running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first

/// The app in front when the run started: the one a test comes back to
/// when it wasn't run from an app (a shell), as by then whoever started the
/// app playing may have brought it forward.
@MainActor var frontAtStart: NSRunningApplication?

/// Opens this run's log and says which app it is.
@MainActor func startRun() {
    frontAtStart = WindowStates.frontPID().flatMap { NSRunningApplication(processIdentifier: $0) }
    runLog.start(app: appName, doing: action.map { $0.rawValue + (via.map { " via \($0.rawValue)" } ?? "") } ?? (readOnly ? "read-only" : "check"))
    say("\(appName) \(CheckedApp.found.version) (\(bundleID))")
    say("  \(appURL.path)")
    say("  " + (running.map { "running, pid \($0.processIdentifier)" } ?? "not running: the menu, sound and Now Playing checks need it running"))
    changes.appPID = running?.processIdentifier ?? 0
}

/// Whether something surer than its menu's or page's word shows whether it
/// plays: its scripted state, or what it reports to Now Playing, which only
/// an administrator can read.
@MainActor var hasSurerSign: Bool { scripting?.hasState == true || (canBeNowPlaying && isAdministrator) }

/// A press by one way reads the menu and the page for their own way (the
/// panel needs the page's player bar, which names the song), or when nothing
/// surer shows whether the app plays.
@MainActor func pressNeeds(_ ways: Set<Way>) -> Bool { !pressingOneWay || via.map(ways.contains) == true || !hasSurerSign }
