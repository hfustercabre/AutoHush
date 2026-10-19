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
    exit(CheckExitStatus.failed)
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

    /// Starts this run's log, named by its time, the app and what it does
    /// (`RunLogName`), and moves the oldest beyond `kept` to the Trash: only
    /// the logs this tool names, as --logs' folder may hold others'.
    func start(app: String, doing: String) {
        let files = FileManager.default
        try? files.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let url = Self.folder.appendingPathComponent(RunLogName.name(at: Date(), app: app, doing: doing))
        guard files.createFile(atPath: url.path, contents: nil), let handle = try? FileHandle(forWritingTo: url) else { return }
        lock.withLock { file = handle }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        write("playercheck " + CommandLine.arguments.dropFirst().joined(separator: " ")
              + "  (pid \(getpid()), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), "
              + (ProcessInfo.processInfo.environment["__CFBundleIdentifier"].map { "run by \($0)" } ?? "run from a shell") + ")")
        let logs = ((try? files.contentsOfDirectory(atPath: Self.folder.path)) ?? []).filter(RunLogName.isRunLog).sorted()
        let discard = discard
        for old in logs.dropLast(Self.kept) { discard(Self.folder.appendingPathComponent(old)) }
    }
}

let runLog = RunLog()

/// A line in the run's log only.
func log(_ line: String) { runLog.write(line) }

/// The input block's line, in the run's log only: it doesn't count as the
/// check going on (the watchdog's minute isn't restarted by it).
func logAside(_ line: String) { runLog.write(line, progress: false) }
