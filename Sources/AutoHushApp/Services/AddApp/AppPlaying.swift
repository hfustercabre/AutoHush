import Foundation
import AutoHushKit

/// Whether the app Add an App checks plays now, as the check will judge it
/// (its Play step waits for this): an output running isn't enough, since a
/// paused app may keep it open, silent (Qobuz did, 2026-10-15: the step went
/// on, then the check asked for it to play); its level decides whenever it
/// can be measured (Audio Recording allowed), else the open output does.
struct AppPlaying: Sendable {
    var outputRunning: @Sendable (pid_t) -> Bool = { OwnedAudioProcesses().isPlayingSound(appPID: $0) }
    var levelMeasured: @Sendable () -> Bool = { TCCAudioCapturePermission().status() == .granted }
    /// Listens for half a second: off the main thread.
    var audible: @Sendable (pid_t) -> Bool = { ProcessTapLevelProbe().isAudible(appPID: $0) }

    func plays(_ pid: pid_t) async -> Bool {
        guard outputRunning(pid) else { return false }
        guard levelMeasured() else { return true }
        let audible = audible
        return await Task.detached { audible(pid) }.value
    }
}
