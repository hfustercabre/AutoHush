import AppKit
import os

/// Mutes the media player's own sound in place of a pause it doesn't take:
/// one that plays on through AutoHush's pause (a trailer that keeps
/// playing), starts again by itself after it, or refuses it (the user,
/// 2026-10-24: "If pauses didn't work, you should mute it").
package protocol PlayerMuting: Sendable {
    /// `false` when it couldn't: not running, no Audio Recording, or AntiDot
    /// mode, which promises no audio taps.
    func mute() async -> Bool
    /// Lets its sound through again; nothing when it isn't muted.
    func unmute() async
    /// Muted, the player relaunched: its new process is muted too. `false`
    /// when that new process couldn't be muted (it's heard).
    func followRelaunch() async -> Bool
}

/// Mutes the running player through process taps (`ProcessTapMuter`).
/// What it muted is noted and read only on `queue`, where the taps are made
/// and taken down, so a mute and an unmute take effect in the order asked.
package final class ProcessPlayerMute: PlayerMuting {
    private let bundleID: String
    private let muter: any AudioMuting
    private let tapsAllowed: @Sendable () -> Bool
    /// The player's running process, `nil` when it isn't running.
    private let running: @Sendable (String) -> pid_t?
    /// Whether macOS allows the taps (Audio Recording), read on `queue`.
    private let audioRecordingAllowed: @Sendable () -> Bool
    /// The process muted, until it's let through again: only on `queue`.
    private let mutedPID = OSAllocatedUnfairLock<pid_t?>(initialState: nil)
    /// Where the taps are made and taken down: never Swift's shared threads.
    private static let queue = DispatchQueue(label: "AutoHush.PlayerMute", qos: .userInitiated)

    /// `tapsAllowed`: whether it may tap now (not in AntiDot mode).
    package init(bundleID: String, muter: any AudioMuting = ProcessTapMuter(),
                 tapsAllowed: @escaping @Sendable () -> Bool,
                 running: @escaping @Sendable (String) -> pid_t? = { NSRunningApplication.running($0)?.processIdentifier },
                 audioRecordingAllowed: @escaping @Sendable () -> Bool = { AudioCapturePermission.allowsTaps }) {
        self.bundleID = bundleID
        self.muter = muter
        self.tapsAllowed = tapsAllowed
        self.running = running
        self.audioRecordingAllowed = audioRecordingAllowed
    }

    package func mute() async -> Bool {
        guard tapsAllowed(), let pid = running(bundleID) else { return false }
        let muter = muter, allowed = audioRecordingAllowed, mutedPID = mutedPID
        return await Self.queue.run {
            guard allowed(), muter.mute(appPID: pid) else { return false }
            mutedPID.withLock { $0 = pid }
            return true
        }
    }

    package func unmute() async {
        let muter = muter, mutedPID = mutedPID
        await Self.queue.run {
            guard let pid = mutedPID.withLock({ muted -> pid_t? in
                defer { muted = nil }
                return muted
            }) else { return }
            muter.unmute(appPID: pid)
        }
    }

    package func followRelaunch() async -> Bool {
        let muter = muter, allowed = audioRecordingAllowed, mutedPID = mutedPID
        let running = running(bundleID), tapsAllowed = tapsAllowed()
        return await Self.queue.run {
            guard let muted = mutedPID.withLock({ $0 }), let running, running != muted else { return true }
            // The old process is gone: nothing of it to hear.
            muter.unmute(appPID: muted)
            mutedPID.withLock { $0 = nil }
            guard tapsAllowed, allowed(), muter.mute(appPID: running) else { return false }
            mutedPID.withLock { $0 = running }
            return true
        }
    }
}
