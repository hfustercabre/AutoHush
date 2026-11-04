import os

/// A state read set once its reader exists: a way of an added app
/// (`CheckedPlayer`), made before the player it belongs to, asks that
/// player's other signs through it (a script that only toggles, a page whose
/// words lag out of sight).
package final class LateState: Sendable {
    private let reader = OSAllocatedUnfairLock<(@Sendable () async -> PlayerState)?>(initialState: nil)

    package init() {}

    package func set(_ read: @escaping @Sendable () async -> PlayerState) {
        reader.withLock { $0 = read }
    }

    /// `.unknown` until it's set.
    package func state() async -> PlayerState {
        guard let read = reader.withLock({ $0 }) else { return .unknown }
        return await read()
    }
}
