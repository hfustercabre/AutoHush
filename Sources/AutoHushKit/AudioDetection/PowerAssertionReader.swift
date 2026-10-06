import Foundation
import IOKit.pwr_mgt

/// A "don't sleep" power assertion a process holds itself, by what it keeps
/// awake and its name.
package struct PowerAssertion: Hashable, Sendable {
    package enum Kind: Hashable, Sendable {
        /// Keeps the Mac awake.
        case system
        /// Keeps only the display awake.
        case display
    }

    package let kind: Kind
    package let name: String

    package init(_ kind: Kind, _ name: String) {
        self.kind = kind
        self.name = name
    }
}

/// Which processes are telling macOS "don't sleep, I'm working" right now.
///
/// Media apps typically hold such an assertion while they play and release it
/// the moment they pause, even when their audio output stays open (measured:
/// Chrome's "Playing audio", VLC's "VLC media playback"). That makes it a
/// playback signal that needs no permission and captures nothing.
package protocol PowerAssertionReading: Sendable {
    /// Each process's own assertions keeping the Mac or the display awake.
    func assertionsByProcess() -> [pid_t: Set<PowerAssertion>]
}

/// Reads the assertions from IOKit's power management.
package struct IOKitPowerAssertionReader: PowerAssertionReading {
    package init() {}

    /// Assertion types that keep the system awake.
    package static let systemSleepTypes: Set<String> = [
        "PreventUserIdleSystemSleep",
        "NoIdleSleepAssertion",
        "PreventSystemSleep",
    ]

    /// Assertion types that keep only the display awake. Video players often
    /// hold them only for video, so alone they don't say an app is playing.
    package static let displaySleepTypes: Set<String> = [
        "PreventUserIdleDisplaySleep",
        "NoDisplaySleepAssertion",
    ]

    package func assertionsByProcess() -> [pid_t: Set<PowerAssertion>] {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let assertions = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [:] }
        return Self.assertionsByProcess(in: assertions)
    }

    /// Keeps only assertions a process holds itself: those created on its
    /// behalf (coreaudiod for every running audio stream, runningboardd for
    /// background tasks) say nothing about playback.
    package static func assertionsByProcess(in assertionsByPID: [NSNumber: [[String: Any]]]) -> [pid_t: Set<PowerAssertion>] {
        var result: [pid_t: Set<PowerAssertion>] = [:]
        for (pid, assertions) in assertionsByPID {
            let own = Set(assertions.compactMap { assertion -> PowerAssertion? in
                guard assertion["AssertionOnBehalfOfPID"] == nil, let type = assertion["AssertType"] as? String else { return nil }
                let name = assertion["AssertName"] as? String ?? ""
                if systemSleepTypes.contains(type) { return PowerAssertion(.system, name) }
                if displaySleepTypes.contains(type) { return PowerAssertion(.display, name) }
                return nil
            })
            if !own.isEmpty { result[pid_t(pid.int32Value)] = own }
        }
        return result
    }
}
