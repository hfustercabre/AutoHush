import CoreAudio
import os

/// The Core Audio processes an app owns: its own and its helpers' (a web
/// app's sound comes from its WebKit process). Every read of a process is a
/// round trip to the audio server, and a Mac has dozens of them, so the
/// answer is kept while the list of audio processes stays the same: asking
/// again then costs one read, plus one per process of the app.
package final class OwnedAudioProcesses: Sendable {
    private let kept = OSAllocatedUnfairLock<(all: [AudioObjectID], appPID: pid_t, owned: [AudioObjectID])?>(initialState: nil)

    package init() {}

    /// The audio processes of the app running as `appPID`.
    package func objects(ownedBy appPID: pid_t) -> [AudioObjectID] {
        let all = Self.allProcesses()
        if let kept = kept.withLock({ $0 }), kept.appPID == appPID, kept.all == all { return kept.owned }
        let owned = Self.objects(ownedBy: appPID, among: all)
        kept.withLock { $0 = (all, appPID, owned) }
        return owned
    }

    /// Whether the app's sound is on: a process of its own has output running.
    package func isPlayingSound(appPID: pid_t) -> Bool {
        objects(ownedBy: appPID).contains {
            CoreAudioProperty.value(kAudioProcessPropertyIsRunningOutput, of: $0, initial: UInt32(0)) == 1
        }
    }

    /// Every audio process on the Mac.
    static func allProcesses() -> [AudioObjectID] {
        CoreAudioProperty.objectIDs(kAudioHardwarePropertyProcessObjectList, of: CoreAudioProperty.systemObject)
    }

    /// The processes among `all` that the app running as `appPID` owns, read
    /// afresh.
    package static func objects(ownedBy appPID: pid_t, among all: [AudioObjectID] = allProcesses()) -> [AudioObjectID] {
        all.filter { object in
            guard let pid = CoreAudioProperty.value(kAudioProcessPropertyPID, of: object, initial: pid_t(0)), pid > 0
            else { return false }
            return ProcessResponsibility.isOwned(pid, by: appPID)
        }
    }
}
