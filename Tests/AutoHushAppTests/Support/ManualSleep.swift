import Foundation

/// Stands in for a sleep the test ends itself: every sleep waits until
/// `timeIsUp()`, and from then on returns at once. A cancelled sleep returns
/// too, as `Task.sleep` does.
final class ManualSleep: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var cancelled: Set<UUID> = []
    private var isOver = false
    private var asked: [Duration] = []

    /// How long each sleep was asked for, in order.
    var durations: [Duration] { lock.withLock { asked } }

    @Sendable func sleep(_ duration: Duration) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let now = lock.withLock { () -> Bool in
                    asked.append(duration)
                    guard !isOver, !cancelled.contains(id) else { return true }
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

    /// Ends every sleep under way, and every one asked for later.
    func timeIsUp() {
        let ended = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOver = true
            defer { waiting = [:] }
            return Array(waiting.values)
        }
        ended.forEach { $0.resume() }
    }
}
