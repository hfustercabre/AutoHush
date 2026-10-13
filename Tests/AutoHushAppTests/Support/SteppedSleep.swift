import Foundation

/// Stands in for a repeated sleep the test moves on itself: every sleep
/// waits for the next `step()`. A cancelled sleep returns, as `Task.sleep`
/// does.
final class SteppedSleep: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var cancelled: Set<UUID> = []

    /// How many sleeps wait for the next step now.
    var sleeping: Int { lock.withLock { waiting.count } }

    @Sendable func sleep(_ duration: Duration) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let now = lock.withLock { () -> Bool in
                    guard !cancelled.contains(id) else { return true }
                    waiting[id] = continuation
                    return false
                }
                if now { continuation.resume() }
            }
        } onCancel: {
            let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                cancelled.insert(id)
                return waiting.removeValue(forKey: id)
            }
            continuation?.resume()
        }
    }

    /// Ends the sleeps under way; later ones wait for the next step.
    func step() {
        let ended = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            defer { waiting = [:] }
            return Array(waiting.values)
        }
        ended.forEach { $0.resume() }
    }
}
