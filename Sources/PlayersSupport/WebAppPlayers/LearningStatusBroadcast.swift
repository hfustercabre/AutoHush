import Foundation
import OSLog
import os
import AutoHushKit

/// A learning status, readable from any thread, and sent to everyone
/// listening when it changes.
final class LearningStatusBroadcast: Sendable {
    private struct State {
        var current: LearningStatus = .learning(hasPlayed: false)
        var listeners: [UUID: AsyncStream<LearningStatus>.Continuation] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var current: LearningStatus { state.withLock { $0.current } }

    /// Tells the listeners, if it changed. They're told under the lock, so
    /// a listener added meanwhile can't get an older status after this one.
    func send(_ status: LearningStatus) {
        state.withLock { state in
            guard state.current != status else { return }
            state.current = status
            state.listeners.values.forEach { $0.yield(status) }
        }
    }

    /// The status now, then each change.
    func updates() -> AsyncStream<LearningStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: LearningStatus.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        state.withLock { state in
            state.listeners[id] = continuation
            continuation.yield(state.current)
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.listeners.removeValue(forKey: id) }
        }
        return stream
    }
}
