import Foundation
import AutoHushKit

/// A check running in the helper: its lines as they come, Stop, its end.
@MainActor
final class PlayerCheckRun {
    private var running: ToolRun.Running?
    private let resultFile: URL
    private var stopped = false
    /// Those waiting for its end (the check's own, and the next check's).
    private var waiting: [CheckedContinuation<PlayerCheckEnd, Never>] = []
    private var end: PlayerCheckEnd?

    init(executable: URL, arguments: [String], result: URL, onLine: @escaping @MainActor @Sendable (String) -> Void) throws {
        resultFile = result
        // Its lines, then its end, each on the main queue in turn, so the
        // end never comes before the last line.
        running = try ToolRun(executable, arguments, readsErrors: true).start(
            onLine: { line in DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line) } } },
            onEnd: { [weak self] ended in DispatchQueue.main.async { MainActor.assumeIsolated { self?.finish(ended.status) } } }
        )
    }

    /// Stops it: it plays the app again if a test paused it, and puts its
    /// window and switches back, first.
    func stop() {
        guard let running, running.isRunning else { return }
        stopped = true
        running.stop()
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
