import os
import AutoHushKit

/// A state read set once its reader exists: a script that only toggles and
/// has no state of its own asks the player it's a way of (`CheckedPlayer`),
/// which is made after its ways.
final class LateState: Sendable {
    private let reader = OSAllocatedUnfairLock<(@Sendable () async -> PlayerState)?>(initialState: nil)

    func set(_ read: @escaping @Sendable () async -> PlayerState) {
        reader.withLock { $0 = read }
    }

    /// `.unknown` until it's set.
    func state() async -> PlayerState {
        guard let read = reader.withLock({ $0 }) else { return .unknown }
        return await read()
    }
}
