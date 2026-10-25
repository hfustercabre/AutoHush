import Foundation
import AutoHushKit

/// Stands in for muting the player's sound in place of a pause
/// (`PlayerMuting`): counts its mutes, unmutes and looks at a relaunch.
/// `works` false, or `allowed` saying no (AntiDot mode), makes a mute fail.
package final class FakeMute: PlayerMuting, @unchecked Sendable {
    // Read and written only under `lock`.
    private let lock = NSLock()
    private let works: Bool
    private let allowed: @Sendable () -> Bool
    private var mutes = 0, unmutes = 0, relaunchLooks = 0
    private var muting: (@Sendable () async -> Void)?
    private var unmuting: (@Sendable () async -> Void)?
    private var relaunchMutes = true

    package init(works: Bool = true, allowed: @escaping @Sendable () -> Bool = { true }) {
        self.works = works
        self.allowed = allowed
    }

    package var muteCount: Int { lock.withLock { mutes } }
    package var unmuteCount: Int { lock.withLock { unmutes } }
    package var relaunchLookCount: Int { lock.withLock { relaunchLooks } }
    /// Runs while it mutes (the monitoring stopping meanwhile).
    package var whileMuting: (@Sendable () async -> Void)? {
        get { lock.withLock { muting } }
        set { lock.withLock { muting = newValue } }
    }
    /// Runs as it unmutes, before it does.
    package var whileUnmuting: (@Sendable () async -> Void)? {
        get { lock.withLock { unmuting } }
        set { lock.withLock { unmuting = newValue } }
    }
    /// Whether a relaunched process could be muted, at each look.
    package var relaunchMuted: Bool {
        get { lock.withLock { relaunchMutes } }
        set { lock.withLock { relaunchMutes = newValue } }
    }

    package func mute() async -> Bool {
        await whileMuting?()
        let allowed = allowed()
        return lock.withLock {
            mutes += 1
            return works && allowed
        }
    }

    package func unmute() async {
        await whileUnmuting?()
        lock.withLock { unmutes += 1 }
    }

    package func followRelaunch() async -> Bool {
        lock.withLock {
            relaunchLooks += 1
            return relaunchMutes
        }
    }
}
