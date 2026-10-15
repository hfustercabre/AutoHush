import Foundation
import os

/// Whether an app is heard now, read once its reader exists: a panel way
/// whose row doesn't follow the app asks the player it's a way of
/// (`CheckedPlayer`), which is made after its ways.
package final class LateHearing: Sendable {
    private let reader = OSAllocatedUnfairLock<(@Sendable (pid_t) async -> Bool?)?>(initialState: nil)

    package init() {}

    package func set(_ read: @escaping @Sendable (pid_t) async -> Bool?) {
        reader.withLock { $0 = read }
    }

    /// `nil` until it's set, and when it can't be told (no Audio Recording,
    /// or AntiDot mode).
    package func heard(_ pid: pid_t) async -> Bool? {
        guard let read = reader.withLock({ $0 }) else { return nil }
        return await read(pid)
    }
}
