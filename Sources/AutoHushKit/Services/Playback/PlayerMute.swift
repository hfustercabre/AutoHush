import AppKit
import os

/// Mutes the media player's own sound in place of a pause it doesn't take:
/// one that plays on through AutoHush's pause (Apple TV's trailers), or
/// starts again by itself after it (the user, 2026-10-24: "If pauses didn't
/// work, you should mute it").
package protocol PlayerMuting: Sendable {
    /// `false` when it couldn't: not running, no Audio Recording, or AntiDot
    /// mode, which promises no audio taps.
    func mute() async -> Bool
    /// Lets its sound through again; nothing when it isn't muted.
    func unmute() async
    /// Muted, the player relaunched: its new process is muted too.
    func followRelaunch() async
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

    package func followRelaunch() async {
        guard let muted = mutedPID.withLock({ $0 }),
              let running = NSRunningApplication.running(bundleID)?.processIdentifier, running != muted else { return }
        await unmute() // the old process is gone: nothing to hear
        _ = await mute()
    }
}
