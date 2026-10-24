import AppKit
import os

/// Mutes the media player's own sound, for one that keeps starting again by
/// itself after AutoHush's pause, an autoplay or an ad (the user, 2026-10-24:
/// "Try to pause it first and if it didn't work, mute it"): the arbiter mutes
/// it only after pausing it again didn't hold.
package protocol PlayerMuting: Sendable {
    /// `false` when it couldn't: not running, no Audio Recording, or AntiDot
    /// mode, which promises no audio taps.
    func mute() async -> Bool
    /// Lets its sound through again; nothing when it isn't muted.
    func unmute() async
}

/// Mutes the running player through process taps (`ProcessTapMuter`).
package final class ProcessPlayerMute: PlayerMuting {
    private let bundleID: String
    private let muter: any AudioMuting
    private let tapsAllowed: @Sendable () -> Bool
    /// The process muted, until it's let through again.
    private let mutedPID = OSAllocatedUnfairLock<pid_t?>(initialState: nil)
    /// Where the taps are made and taken down: never Swift's shared threads.
    private static let queue = DispatchQueue(label: "AutoHush.PlayerMute", qos: .userInitiated)

    /// `tapsAllowed`: whether it may tap now (not in AntiDot mode).
    package init(bundleID: String, muter: any AudioMuting = ProcessTapMuter(),
                 tapsAllowed: @escaping @Sendable () -> Bool) {
        self.bundleID = bundleID
        self.muter = muter
        self.tapsAllowed = tapsAllowed
    }

    package func mute() async -> Bool {
        guard tapsAllowed(), AudioCapturePermission.allowsTaps,
              let pid = NSRunningApplication.running(bundleID)?.processIdentifier else { return false }
        let muter = muter
        guard await Self.queue.run({ muter.mute(appPID: pid) }) else { return false }
        mutedPID.withLock { $0 = pid }
        return true
    }

    package func unmute() async {
        guard let pid = mutedPID.withLock({ muted -> pid_t? in
            defer { muted = nil }
            return muted
        }) else { return }
        let muter = muter
        await Self.queue.run { muter.unmute(appPID: pid) }
    }
}

/// How long ago the user last pressed a key, clicked or moved the pointer
/// (any input event macOS counts, this login's).
package enum UserInput {
    package static func secondsSinceLast() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
