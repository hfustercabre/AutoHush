import Foundation
import AutoHushKit

/// Whether the app Add an App checks plays now, as the check will judge it
/// (its Play step waits for this): an output running isn't enough, since a
/// paused app may keep it open, silent (Qobuz did, 2026-10-15: the step went
/// on, then the check asked for it to play); its level decides whenever it
/// can be measured (Audio Recording allowed), else the open output does.
struct AppPlaying: Sendable {
    /// One for every poll of the step: it keeps the app's audio processes
    /// while the Mac's stay the same, as reading them all takes dozens of
    /// round trips to the audio server.
    private static let processes = OwnedAudioProcesses()

    var outputRunning: @Sendable (pid_t) -> Bool = { AppPlaying.processes.isPlayingSound(appPID: $0) }
    var levelMeasured: @Sendable () -> Bool = { TCCAudioCapturePermission().status() == .granted }
    var audible: @Sendable (pid_t) -> Bool = { ProcessTapLevelProbe().isAudible(appPID: $0) }

    /// Reading the audio processes and listening block: done here, one at
    /// a time, as `CheckedPlayer` listens on a queue of its own.
    private static let queue = DispatchQueue(label: "AutoHush.AppPlaying", qos: .userInitiated)

    /// Reads the audio processes, and listens for half a second: off the
    /// main thread, and off Swift's shared threads.
    func plays(_ pid: pid_t) async -> Bool {
        let (outputRunning, levelMeasured, audible) = (outputRunning, levelMeasured, audible)
        return await Self.queue.run {
            guard outputRunning(pid) else { return false }
            guard levelMeasured() else { return true }
            return audible(pid)
        }
    }
}
