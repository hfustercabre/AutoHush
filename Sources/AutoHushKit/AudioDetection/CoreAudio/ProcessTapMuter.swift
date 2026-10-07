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
/// on the app's processes, muted while it's read, read by a private
/// aggregate device whose IO block throws the samples away (`ProcessTap`).
/// macOS mutes nothing for a tap that nothing reads: a bare muted tap left a
/// YouTube Music ad audible (2026-10-07). Nothing is kept or rerouted;
/// removing the tap unmutes, and taps die with AutoHush, so quitting unmutes
/// too.
package final class ProcessTapMuter: AudioMuting {
    private let taps = OSAllocatedUnfairLock<[pid_t: ProcessTap]>(initialState: [:])
    private let ioQueue = DispatchQueue(label: "AutoHush.Muter.io", qos: .userInitiated)
    private let logger = Logger(category: "AudioMonitor")

    package init() {}

    package func mute(appPID: pid_t) -> Bool {
        if taps.withLock({ $0[appPID] }) != nil { return true }
        let processes = Self.processObjects(ownedBy: appPID)
        guard !processes.isEmpty else { return false }
        let tap: ProcessTap
        do {
            tap = try ProcessTap(processObjectIDs: processes, muted: true, ioQueue: ioQueue)
        } catch {
            logger.error("[mute] couldn't mute pid \(appPID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
        let kept = taps.withLock { taps in
            guard taps[appPID] == nil else { return false }
            taps[appPID] = tap
            return true
        }
        if !kept { tap.invalidate() } // muted meanwhile
        logger.notice("[mute] muted pid \(appPID, privacy: .public) (\(processes.count, privacy: .public) audio processes)")
        return true
    }

    package func unmute(appPID: pid_t) {
        guard let tap = taps.withLock({ $0.removeValue(forKey: appPID) }) else { return }
        tap.invalidate()
        logger.notice("[mute] unmuted pid \(appPID, privacy: .public)")
    }

    deinit {
        taps.withLock { $0.values }.forEach { $0.invalidate() }
    }

    /// The Core Audio processes of the app and of its helpers (a web app's
    /// sound comes from its WebKit process).
    static func processObjects(ownedBy appPID: pid_t) -> [AudioObjectID] {
        CoreAudioProperty.objectIDs(kAudioHardwarePropertyProcessObjectList, of: CoreAudioProperty.systemObject).filter { object in
            guard let pid = CoreAudioProperty.value(kAudioProcessPropertyPID, of: object, initial: pid_t(0)), pid > 0 else { return false }
            return ProcessResponsibility.isOwned(pid, by: appPID)
        }
    }
}
