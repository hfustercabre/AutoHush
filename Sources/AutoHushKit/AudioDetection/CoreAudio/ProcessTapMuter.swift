import CoreAudio
import Foundation
import OSLog
import os

/// Silences an app without pausing it, for a player that refuses to pause
/// (a web app's button disabled during an ad). Callers try pausing first.
package protocol AudioMuting: Sendable {
    /// Mutes every audio process the app running as `appPID` owns; `false`
    /// when it couldn't (no such process, or no System Audio Recording
    /// permission).
    func mute(appPID: pid_t) -> Bool
    /// Lets its sound through again; nothing when it isn't muted.
    func unmute(appPID: pid_t)
}

/// Mutes apps through Core Audio's process taps (public, macOS 14.2+): a tap
/// whose `muteBehavior` is `.muted` keeps the tapped processes' sound from
/// reaching the speakers for as long as it exists. Nothing reads it, and
/// nothing is rerouted; removing the tap unmutes. Taps die with AutoHush, so
/// quitting unmutes too.
package final class ProcessTapMuter: AudioMuting {
    private let taps = OSAllocatedUnfairLock<[pid_t: AudioObjectID]>(initialState: [:])
    private let logger = Logger(category: "AudioMonitor")

    package init() {}

    package func mute(appPID: pid_t) -> Bool {
        if taps.withLock({ $0[appPID] }) != nil { return true }
        let processes = Self.processObjects(ownedBy: appPID)
        guard !processes.isEmpty else { return false }
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .muted
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            logger.error("[mute] couldn't mute pid \(appPID, privacy: .public): OSStatus \(status, privacy: .public)")
            return false
        }
        taps.withLock { [tapID] in $0[appPID] = tapID }
        logger.notice("[mute] muted pid \(appPID, privacy: .public) (\(processes.count, privacy: .public) audio processes)")
        return true
    }

    package func unmute(appPID: pid_t) {
        guard let tapID = taps.withLock({ $0.removeValue(forKey: appPID) }) else { return }
        AudioHardwareDestroyProcessTap(tapID)
        logger.notice("[mute] unmuted pid \(appPID, privacy: .public)")
    }

    deinit {
        for tapID in taps.withLock({ $0.values }) { AudioHardwareDestroyProcessTap(tapID) }
    }

    /// The Core Audio processes of the app and of its helpers (a web app's
    /// sound comes from its WebKit process).
    private static func processObjects(ownedBy appPID: pid_t) -> [AudioObjectID] {
        CoreAudioProperty.objectIDs(kAudioHardwarePropertyProcessObjectList, of: CoreAudioProperty.systemObject).filter { object in
            guard let pid = CoreAudioProperty.value(kAudioProcessPropertyPID, of: object, initial: pid_t(0)), pid > 0 else { return false }
            return ProcessResponsibility.isOwned(pid, by: appPID)
        }
    }
}
