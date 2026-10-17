import Foundation

/// AutoHush's own playercheck (in Contents/Helpers), which Add an App…
/// runs: a check of an app in a process of its own, so a check that ends,
/// is stopped or crashes takes its block on the mouse and keyboard with it;
/// and the questions it answers about apps. Its logs and caches go in
/// AutoHush's own folders.
struct PlayerCheckHelper: Sendable {
    let url: URL
    /// Where its checks' logs go: `logsFolder`, unless a test gives its own.
    var logs = PlayerCheckHelper.logsFolder
    /// What it learns about apps: `cachesFolder`, unless a test gives its own.
    var caches = PlayerCheckHelper.cachesFolder

    init(url: URL) {
        self.url = url
    }

    /// The helper inside AutoHush.app; in a build run straight from .build
    /// (the harness), the one built beside it.
    static var bundled: PlayerCheckHelper? { bundled(in: Bundle.main.bundleURL, beside: Bundle.main.executableURL) }

    /// The helper inside the app at `app`, else the one beside `executable`,
    /// where it can run.
    static func bundled(in app: URL, beside executable: URL?) -> PlayerCheckHelper? {
        let candidates = [app.appending(path: "Contents/Helpers/playercheck"),
                          executable?.deletingLastPathComponent().appending(path: "playercheck")]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }.map(PlayerCheckHelper.init)
    }

    /// Where its checks' logs go: beside AutoHush's own.
    static let logsFolder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/AutoHush/Checks")
    /// What it learns about apps (their page's button, their words), in
    /// AutoHush's caches.
    static let cachesFolder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Caches/\(Bundle.main.bundleIdentifier ?? "com.autohush.AutoHush")/PlayerCheck")
    /// The folders every run is given.
    var folderArguments: [String] { ["--logs", logs.path, "--caches", caches.path] }

    /// How far back the Now Playing list is read: enough for the apps used
    /// lately, without reading back to the Mac's start.
    static let nowPlayingHours = 24
    /// How long a question may take before it's given up (a check itself
    /// has none: it's stopped by the user, or ends with AutoHush).
    static let questionTimeout: TimeInterval = 30

    /// Runs it with `arguments` until it ends, or for `timeout` at most:
    /// what it printed, and how it ended (-1 when it couldn't start or
    /// took too long).
    func run(_ arguments: [String], timeout: TimeInterval = PlayerCheckHelper.questionTimeout) async -> (status: Int32, output: String) {
        let url = url
        let arguments = arguments + folderArguments
        return await Task.detached {
            let process = Process()
            process.executableURL = url
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return (-1, "") }
            let late = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: late)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            late.cancel()
            let timedOut = process.terminationReason == .uncaughtSignal
            return (timedOut ? -1 : process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }

    /// The apps macOS keeps in Now Playing (from its log, which only an
    /// administrator can read), by bundle ID: whether each plays.
    func nowPlaying() async -> [String: Bool] {
        let (status, output) = await run(["--now-playing-list", String(Self.nowPlayingHours)])
        return status == 0 ? Self.nowPlaying(fromList: output) : [:]
    }

    /// `--now-playing-list`'s lines: "<bundle ID>\t<pid>\t<state>\t<1 if
    /// active>\t<name>", then "#active\t<pid>".
    static func nowPlaying(fromList output: String) -> [String: Bool] {
        var apps: [String: Bool] = [:]
        for line in output.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, !fields[0].isEmpty, fields[2] != "Removed" else { continue }
            apps[fields[0]] = fields[2] == "Playing"
        }
        return apps
    }

    /// Which of the apps at `urls` can be in Now Playing (they can play),
    /// by their paths.
    func canPlay(_ urls: [URL]) async -> Set<String> {
        guard !urls.isEmpty else { return [] }
        let (status, output) = await run(["--now-playing-reasons"] + urls.map(\.path))
        return status == 0 ? Self.canPlay(fromReasons: output) : []
    }

    /// `--now-playing-reasons`' lines: "<path>\t<reason>\t<framework>\t<switches>",
    /// each empty when none.
    static func canPlay(fromReasons output: String) -> Set<String> {
        Set(output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            return fields.count >= 2 && !fields[1].isEmpty ? String(fields[0]) : nil
        })
    }

    /// Whether the app at `url`, running, was opened with the launch option
    /// it needs; `nil` when it needs none or isn't running.
    func runsWithLaunchOption(_ url: URL) async -> Bool? {
        let (status, output) = await run(["--launch-option", url.path])
        return status == 0 ? Self.runsWithLaunchOption(fromAnswer: output) : nil
    }

    /// `--launch-option`'s answer: "<option>\t<yes|no|…>".
    static func runsWithLaunchOption(fromAnswer output: String) -> Bool? {
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        guard fields.count == 2, !fields[0].isEmpty else { return nil }
        return fields[1] == "yes" ? true : fields[1] == "no" ? false : nil
    }

    /// Quits the app at `url` (never by force) and opens it again, in the
    /// background, with the launch option it needs; or opens it so when it
    /// isn't running. Whether it did.
    func reopenWithLaunchOption(_ url: URL) async -> Bool {
        await run(["--relaunch", url.path], timeout: 60).status == 0
    }

    /// Starts a check of the app at `appURL`, blocking the mouse and
    /// keyboard while it moves the app's window (Escape stops it): each line
    /// of its report to `onLine` as it comes, its result once it ends.
    /// `taps`: false in AntiDot mode, which taps no sound (the app isn't
    /// muted, and whether it plays is told by other signs).
    @MainActor
    func check(_ appURL: URL, taps: Bool, onLine: @escaping @MainActor @Sendable (String) -> Void) throws -> PlayerCheckRun {
        let result = FileManager.default.temporaryDirectory.appending(path: "AutoHush check \(UUID().uuidString).json")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return try PlayerCheckRun(executable: url, arguments: checkArguments(appURL, result: result, taps: taps),
                                  result: result, onLine: onLine)
    }

    /// A check's arguments. --partial: the window said what's missing, and
    /// the check goes on without what isn't needed.
    func checkArguments(_ appURL: URL, result: URL, taps: Bool) -> [String] {
        [appURL.path, "--block-input", "--partial", "--result", result.path] + folderArguments + (taps ? [] : ["--no-taps"])
    }

    /// The newest check's log, to show after a check couldn't finish.
    static var newestLog: URL? { newestLog(in: logsFolder) }

    /// The newest log in `folder`.
    static func newestLog(in folder: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.max { lhs, rhs in
            let date = { (url: URL) in (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
            return date(lhs) < date(rhs)
        }
    }
}
