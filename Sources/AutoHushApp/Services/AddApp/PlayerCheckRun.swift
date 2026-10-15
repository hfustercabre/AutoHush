import Foundation

/// A check running in the helper: its lines as they come, Stop, its end.
@MainActor
final class PlayerCheckRun {
    private let process = Process()
    private let resultFile: URL
    private var stopped = false
    /// Those waiting for its end (the check's own, and the next check's).
    private var waiting: [CheckedContinuation<PlayerCheckEnd, Never>] = []
    private var end: PlayerCheckEnd?

    init(executable: URL, arguments: [String], result: URL, onLine: @escaping @MainActor @Sendable (String) -> Void) throws {
        resultFile = result
        process.executableURL = executable
        process.arguments = arguments
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
        return await withCheckedContinuation { waiting.append($0) }
    }

    private func finish(_ status: Int32) {
        let end = PlayerCheckEnd.of(status: status, stopped: stopped, result: try? Data(contentsOf: resultFile))
        try? FileManager.default.removeItem(at: resultFile)
        self.end = end
        waiting.forEach { $0.resume(returning: end) }
        waiting = []
    }
}
