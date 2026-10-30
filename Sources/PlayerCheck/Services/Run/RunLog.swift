import Foundation
import os
import PlayerCheckKit

/// Each check or press of an app (and each relaunch) is also written, whole
/// (the quiet parts of a press too) and with each line's time, to a file of
/// its own in ~/Library/Logs/PlayerCheck (or --logs' folder: AutoHush's
/// Checks), the last `kept` kept: a run whose result went wrong can be read
/// afterwards, though a later check replaced it. A stop writes to it from
/// another thread, so it's behind a lock.
final class RunLog: Sendable {
    static let folder = logsFolder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PlayerCheck")
    static let kept = 50
    private struct State {
        var file: FileHandle?
        /// When the check last wrote a line of its own (not the input block's).
        var last = Date()
        var discard: @Sendable (URL) -> Void = { try? FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// How a log beyond `kept` goes: to the Trash. Tests note it instead.
    var discard: @Sendable (URL) -> Void {
        get { state.withLock { $0.discard } }
        set { state.withLock { $0.discard = newValue } }
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
        state.withLock {
            if progress { $0.last = Date() }
            // Throws on failure (a full disk), where `write(_:)` raises an exception.
            try? $0.file?.write(contentsOf: Data("\(time.string(from: Date()))  \(line)\n".utf8))
        }
    }

    /// When the check last wrote a line of its own (`InputBlock`'s watchdog).
    var lastWrite: Date { state.withLock { $0.last } }

    /// Starts this run's log, named by its time, the app and what it does
    /// (`RunLogName`), and moves the oldest beyond `kept` to the Trash: only
    /// the logs this tool names, as --logs' folder may hold others'.
    func start(app: String, doing: String) {
        let files = FileManager.default
        try? files.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let url = Self.folder.appendingPathComponent(RunLogName.name(at: Date(), app: app, doing: doing))
        guard files.createFile(atPath: url.path, contents: nil), let handle = try? FileHandle(forWritingTo: url) else { return }
        state.withLock { $0.file = handle }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        write("playercheck " + CommandLine.arguments.dropFirst().joined(separator: " ")
              + "  (pid \(getpid()), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), "
              + (ProcessInfo.processInfo.environment["__CFBundleIdentifier"].map { "run by \($0)" } ?? "run from a shell") + ")")
        let logs = ((try? files.contentsOfDirectory(atPath: Self.folder.path)) ?? []).filter(RunLogName.isRunLog).sorted()
        let discard = discard
        for old in logs.dropLast(Self.kept) { discard(Self.folder.appendingPathComponent(old)) }
    }
}
