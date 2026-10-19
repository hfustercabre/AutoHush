import Foundation
import os

/// Stands in for a sleep the test ends itself. Every sleep waits until the
/// next `step()` (a repeated sleep, moved on one round at a time), or until
/// `timeIsUp()`, after which every sleep returns at once. A cancelled sleep
/// returns too, as `Task.sleep` does.
package final class ManualSleep: Sendable {
    private struct State {
        var waiting: [UUID: CheckedContinuation<Void, Never>] = [:]
        var cancelled: Set<UUID> = []
        var isOver = false
        var asked: [Duration] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    package init() {}

    /// How long each sleep was asked for, in order.
    package var durations: [Duration] { state.withLock { $0.asked } }

    /// How many sleeps wait now.
    package var sleeping: Int { state.withLock { $0.waiting.count } }

    @Sendable package func sleep(_ duration: Duration) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let now = state.withLockUnchecked { state -> Bool in
                    state.asked.append(duration)
                    guard !state.isOver, !state.cancelled.contains(id) else { return true }
                    state.waiting[id] = continuation
                    return false
                }
                if now { continuation.resume() }
            }
        } onCancel: {
            let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
                state.cancelled.insert(id)
                return state.waiting.removeValue(forKey: id)
            }
            continuation?.resume()
        }
    }

    /// Ends the sleeps under way; later ones wait for the next step.
    package func step() {
        end(forGood: false)
    }

    /// Ends every sleep under way, and every one asked for later.
    package func timeIsUp() {
        end(forGood: true)
    }

    private func end(forGood: Bool) {
        let ended = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            if forGood { state.isOver = true }
            defer { state.waiting = [:] }
            return Array(state.waiting.values)
        }
        ended.forEach { $0.resume() }
    }
}
