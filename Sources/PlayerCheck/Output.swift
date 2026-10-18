import Foundation
import PlayerCheckKit

// MARK: - The report

/// Set for --play and --pause: the checks run silently, then one line says what was done.
@MainActor var quiet = action != nil

/// A line of the report: printed (unless `quiet`) and logged. No line holds
/// the home folder's path (`~` instead), nor what was playing
/// (`PrivateText`): the log may be posted in an issue.
@MainActor func say(_ line: String = "") {
    let line = PrivateText.redacted(line)
    log(line)
    guard !quiet else { return }
    print(line)
    fflush(nil)
}

/// `text` with --developer, else nothing: the report's parts that name
/// AutoHush's own types, for whoever adds a player to the code.
func forDevelopers(_ text: String) -> String { developer ? text : "" }

/// Says why it can't go on, and ends.
func fail(_ line: String) -> Never {
    let line = PrivateText.redacted(line)
    log("playercheck: \(line)")
    FileHandle.standardError.write(Data("playercheck: \(line)\n".utf8))
    exit(1)
}

// MARK: - The run's log

/// Each check or press of an app (and each relaunch) is also written, whole
/// (the quiet parts of a press too) and with each line's time, to a file of
/// its own in ~/Library/Logs/PlayerCheck (or --logs' folder: AutoHush's
/// Checks), the last `kept` kept: a run whose result went wrong can be read
/// afterwards, though a later check replaced it. A stop writes to it from
/// another thread, so it's behind a lock.
final class RunLog: @unchecked Sendable {
    static let folder = logsFolder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PlayerCheck")
    static let kept = 50
    private let lock = NSLock()
    private var file: FileHandle?
    /// When the check last wrote a line of its own (not the input block's).
    private var last = Date()
    private var _discard: @Sendable (URL) -> Void = { try? FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    /// How a log beyond `kept` goes: to the Trash. Tests note it instead.
    var discard: @Sendable (URL) -> Void {
        get { lock.withLock { _discard } }
        set { lock.withLock { _discard = newValue } }
    }
    private let time: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "HH:mm:ss.SSS"
        return format
    }()

    /// Writes `line` (the home folder written `~`); `progress` false for the
    /// input block's own lines, which don't show the check going on.
    func write(_ line: String, progress: Bool = true) {
        let line = PrivateText.redacted(line)
        lock.withLock {
            if progress { last = Date() }
            file?.write(Data("\(time.string(from: Date()))  \(line)\n".utf8))
        }
    }

    /// When the check last wrote a line of its own (`InputBlock`'s watchdog).
    var lastWrite: Date { lock.withLock { last } }

    /// Starts this run's log, named by its time, the app and what it does,
    /// and moves the oldest beyond `kept` to the Trash: only the logs this
    /// tool names (`isRunLog`), as --logs' folder may hold others'.
    func start(app: String, doing: String) {
        let files = FileManager.default
        try? files.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let safe = { (text: String) in text.map { "/:".contains($0) ? "-" : String($0) }.joined() }
        let url = Self.folder.appendingPathComponent("\(Self.nameTime().string(from: Date())) \(safe(app)) \(safe(doing)).log")
        guard files.createFile(atPath: url.path, contents: nil), let handle = try? FileHandle(forWritingTo: url) else { return }
        lock.withLock { file = handle }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        write("playercheck " + CommandLine.arguments.dropFirst().joined(separator: " ")
              + "  (pid \(getpid()), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), "
              + (ProcessInfo.processInfo.environment["__CFBundleIdentifier"].map { "run by \($0)" } ?? "run from a shell") + ")")
        let logs = ((try? files.contentsOfDirectory(atPath: Self.folder.path)) ?? []).filter(Self.isRunLog).sorted()
        let discard = discard
        for old in logs.dropLast(Self.kept) { discard(Self.folder.appendingPathComponent(old)) }
    }

    /// The time a run's log is named by, e.g. "2026-10-18 09.41.07.250".
    private static func nameTime() -> DateFormatter {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return format
    }

    /// What a run does, last in its log's name: a check, a press (by a way),
    /// a relaunch.
    static let doings: Set<String> = Set(["check", "read-only", "relaunch"] + Action.allCases.flatMap { action in
        [action.rawValue] + Way.allCases.map { "\(action.rawValue) via \($0.rawValue)" }
    })

    /// Whether `name` is a run's log as `start` names it: its time, the app,
    /// what the run did, ".log".
    static func isRunLog(_ name: String) -> Bool {
        guard name.hasSuffix(".log"), name.count > 24 else { return false }
        let time = String(name.prefix(23)), rest = name.dropFirst(23).dropLast(4)
        guard rest.first == " ", nameTime().date(from: time) != nil else { return false }
        return doings.contains { rest.hasSuffix(" " + $0) && rest.count > $0.count + 2 }
    }
}

let runLog = RunLog()

/// A line in the run's log only.
func log(_ line: String) { runLog.write(line) }

/// The input block's line, in the run's log only: it doesn't count as the
/// check going on (the watchdog's minute isn't restarted by it).
func logAside(_ line: String) { runLog.write(line, progress: false) }
