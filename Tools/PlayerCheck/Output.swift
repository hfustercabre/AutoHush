import Foundation

// MARK: - The report

/// Set for --play and --pause: the checks run silently, then one line says what was done.
@MainActor var quiet = action != nil

/// A line of the report: printed (unless `quiet`) and logged.
@MainActor func say(_ line: String = "") {
    log(line)
    guard !quiet else { return }
    print(line)
    fflush(nil)
}

/// Says why it can't go on, and ends.
func fail(_ line: String) -> Never {
    log("playercheck: \(line)")
    FileHandle.standardError.write(Data("playercheck: \(line)\n".utf8))
    exit(1)
}

// MARK: - The run's log

/// Each check or press of an app is also written, whole (the quiet parts of
/// a press too) and with each line's time, to a file of its own in
/// ~/Library/Logs/PlayerCheck, the last `kept` kept: a run whose result went
/// wrong can be read afterwards, though a later check replaced it in Player
/// Check. A stop writes to it from another thread, so it's behind a lock.
final class RunLog: @unchecked Sendable {
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PlayerCheck")
    static let kept = 50
    private let lock = NSLock()
    private var file: FileHandle?
    private var last = Date()
    private let time: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "HH:mm:ss.SSS"
        return format
    }()

    func write(_ line: String) {
        lock.withLock {
            last = Date()
            file?.write(Data("\(time.string(from: Date()))  \(line)\n".utf8))
        }
    }

    /// When the run last wrote a line (`InputBlock`'s watchdog).
    var lastWrite: Date { lock.withLock { last } }

    /// Starts this run's log, named by its time, the app and what it does,
    /// and removes the oldest beyond `kept` (files this tool wrote).
    func start(app: String, doing: String) {
        let files = FileManager.default
        try? files.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let name = DateFormatter()
        name.locale = Locale(identifier: "en_US_POSIX")
        name.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        let safe = { (text: String) in text.map { "/:".contains($0) ? "-" : String($0) }.joined() }
        let url = Self.folder.appendingPathComponent("\(name.string(from: Date())) \(safe(app)) \(safe(doing)).log")
        guard files.createFile(atPath: url.path, contents: nil), let handle = try? FileHandle(forWritingTo: url) else { return }
        lock.withLock { file = handle }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        write("playercheck " + CommandLine.arguments.dropFirst().joined(separator: " ")
              + "  (pid \(getpid()), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), "
              + (ProcessInfo.processInfo.environment["__CFBundleIdentifier"].map { "run by \($0)" } ?? "run from a shell") + ")")
        let logs = ((try? files.contentsOfDirectory(atPath: Self.folder.path)) ?? []).filter { $0.hasSuffix(".log") }.sorted()
        for old in logs.dropLast(Self.kept) { try? files.removeItem(at: Self.folder.appendingPathComponent(old)) }
    }
}

let runLog = RunLog()

/// A line in the run's log only.
func log(_ line: String) { runLog.write(line) }
