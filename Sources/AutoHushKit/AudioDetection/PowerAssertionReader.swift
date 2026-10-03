import Foundation
import IOKit.pwr_mgt

/// Which processes are telling macOS "don't sleep, I'm working" right now.
///
/// Media apps typically hold such an assertion while they play and release it
/// the moment they pause, even when their audio output stays open (measured:
/// Chrome's "Playing audio", VLC's "VLC media playback"). That makes it a
/// playback signal that needs no permission and captures nothing.
package protocol PowerAssertionReading: Sendable {
    /// PIDs holding their own system-sleep assertion.
    func pidsKeepingSystemAwake() -> Set<pid_t>
}

/// Reads the assertions from IOKit's power management.
package struct IOKitPowerAssertionReader: PowerAssertionReading {
    package init() {}

    /// Assertion types that keep the system (not just the display) awake.
    /// Display-only assertions are left out: video players often hold them
    /// only for video, so audio-only playback would look paused.
    package static let systemSleepTypes: Set<String> = [
        "PreventUserIdleSystemSleep",
        "NoIdleSleepAssertion",
        "PreventSystemSleep",
    ]

    package func pidsKeepingSystemAwake() -> Set<pid_t> {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let assertions = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }
        return Self.pidsKeepingSystemAwake(in: assertions)
    }

    /// Counts only assertions a process holds itself: those created on its
    /// behalf (coreaudiod for every running audio stream, runningboardd for
    /// background tasks) say nothing about playback.
    package static func pidsKeepingSystemAwake(in assertionsByPID: [NSNumber: [[String: Any]]]) -> Set<pid_t> {
        var pids = Set<pid_t>()
        for (pid, assertions) in assertionsByPID {
            let ownSystemSleep = assertions.contains { assertion in
                assertion["AssertionOnBehalfOfPID"] == nil
                    && systemSleepTypes.contains(assertion["AssertType"] as? String ?? "")
            }
            if ownSystemSleep { pids.insert(pid_t(pid.int32Value)) }
        }
        return pids
    }
}
