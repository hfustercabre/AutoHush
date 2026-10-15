import Foundation
import CheckedPlayers

/// AutoHush's own playercheck (in Contents/Helpers), which Add an App…
/// runs: a check of an app in a process of its own, so a check that ends,
/// is stopped or crashes takes its block on the mouse and keyboard with it;
/// and the questions it answers about apps.
struct PlayerCheckHelper: Sendable {
    let url: URL

    /// The helper inside AutoHush.app; in a build run straight from .build
    /// (the harness), the one built beside it.
    static var bundled: PlayerCheckHelper? {
        let candidates = [Bundle.main.bundleURL.appending(path: "Contents/Helpers/playercheck"),
                          Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "playercheck")]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }.map(PlayerCheckHelper.init)
    }

    /// Where its checks' logs go: beside AutoHush's own.
    static let logsFolder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/AutoHush/Checks")

    /// Runs it with `arguments` until it ends: what it printed, and how it ended.
    func run(_ arguments: [String]) async -> (status: Int32, output: String) {
        let url = url
        return await Task.detached {
            let process = Process()
            process.executableURL = url
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return (-1, "") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }

    /// The apps macOS keeps in Now Playing (from its log, which only an
    /// administrator can read), by bundle ID: whether each plays.
    func nowPlaying() async -> [String: Bool] {
        let (status, output) = await run(["--now-playing-list"])
        guard status == 0 else { return [:] }
        var apps: [String: Bool] = [:]
        // "<bundle ID>\t<pid>\t<state>\t<1 if active>\t<name>", then "#active\t<pid>".
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
        guard status == 0 else { return [] }
        // "<path>\t<reason>\t<framework>\t<switches>", each empty when none.
        return Set(output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            return fields.count >= 2 && !fields[1].isEmpty ? String(fields[0]) : nil
        })
    }

    /// Whether the app at `url`, running, was opened with the launch option
    /// it needs; `nil` when it needs none or isn't running.
    func runsWithLaunchOption(_ url: URL) async -> Bool? {
        let (status, output) = await run(["--launch-option", url.path])
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        guard status == 0, fields.count == 2, !fields[0].isEmpty else { return nil }
        return fields[1] == "yes" ? true : fields[1] == "no" ? false : nil
    }

    /// Quits the app at `url` (never by force) and opens it again, in the
    /// background, with the launch option it needs; or opens it so when it
    /// isn't running. Whether it did.
    func reopenWithLaunchOption(_ url: URL) async -> Bool {
        await run(["--relaunch", url.path]).status == 0
    }

    /// Starts a check of the app at `url`, blocking the mouse and keyboard
    /// while it moves the app's window (Escape stops it): each line of its
    /// report to `onLine` as it comes, its result once it ends.
    @MainActor
    func check(_ appURL: URL, onLine: @escaping @MainActor @Sendable (String) -> Void) throws -> PlayerCheckRun {
        let result = FileManager.default.temporaryDirectory.appending(path: "AutoHush check \(UUID().uuidString).json")
        try? FileManager.default.createDirectory(at: Self.logsFolder, withIntermediateDirectories: true)
        return try PlayerCheckRun(executable: url, appURL: appURL, result: result, logs: Self.logsFolder, onLine: onLine)
    }
}

/// How a check ended.
enum PlayerCheckEnd: Equatable {
    /// It went through: what it found (`nil` if it wrote nothing).
    case finished(CheckResult?)
    /// Stopped (Stop, Escape, or its window closed): what it changed is put back.
    case stopped
    /// It didn't start: a permission it needs is missing (it checks them
    /// all before doing anything).
    case permissionMissing
    /// It ended otherwise, with this exit status.
    case failed(Int32)
}

/// A check running in the helper: its lines as they come, Stop, its end.
@MainActor
final class PlayerCheckRun {
    private let process = Process()
    private let resultFile: URL
    private var stopped = false
    private var ended: CheckedContinuation<PlayerCheckEnd, Never>?
    private var end: PlayerCheckEnd?

    init(executable: URL, appURL: URL, result: URL, logs: URL, onLine: @escaping @MainActor @Sendable (String) -> Void) throws {
        resultFile = result
        process.executableURL = executable
        // --partial: the window said what's missing, and the user went on without it.
        process.arguments = [appURL.path, "--block-input", "--partial", "--result", result.path, "--logs", logs.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Its lines, then its end, each on the main queue in turn, so the
        // end never comes before the last line.
        let handle = pipe.fileHandleForReading
        let process = process
        Thread.detachNewThread { [weak self] in
            var pending = Data()
            while case let data = handle.availableData, !data.isEmpty {
                pending.append(data)
                while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line) } }
                }
            }
            process.waitUntilExit()
            let status = process.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finish(status) } }
        }
    }

    /// Stops it: it plays the app again if a test paused it, and puts its
    /// window and switches back, first.
    func stop() {
        guard process.isRunning else { return }
        stopped = true
        process.terminate()
    }

    /// How it ended, once it has.
    func waitForEnd() async -> PlayerCheckEnd {
        if let end { return end }
        return await withCheckedContinuation { ended = $0 }
    }

    private func finish(_ status: Int32) {
        let end: PlayerCheckEnd
        switch status {
        case 0:
            end = .finished((try? Data(contentsOf: resultFile)).flatMap { try? JSONDecoder().decode(CheckResult.self, from: $0) })
        case 3: end = .permissionMissing
        default: end = stopped || status == 143 || status == 130 ? .stopped : .failed(status)
        }
        try? FileManager.default.removeItem(at: resultFile)
        self.end = end
        ended?.resume(returning: end)
        ended = nil
    }
}
