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
/// YouTube Music ad audible (on macOS 27). Nothing is kept or rerouted;
/// removing the tap unmutes, and taps die with AutoHush, so quitting unmutes
/// too.
///
/// While an app is muted, its audio processes are looked at again every
/// `recheckInterval`: one it starts later (a helper that plays for it) is
/// muted too, a new tap made over them all before the old one goes. A set
/// that can't be tapped is tried again at the next look.
package final class ProcessTapMuter: AudioMuting {
    /// How often a muted app's audio processes are looked at again.
    package static let recheckInterval: TimeInterval = 1

    private struct Muted {
        var tap: ProcessTap
        var processes: Set<AudioObjectID>
        /// Its processes, kept between looks (one read while they stay the same).
        let owned: OwnedAudioProcesses
    }

    private let taps = OSAllocatedUnfairLock<[pid_t: Muted]>(initialState: [:])
    private let ioQueue = DispatchQueue(label: "AutoHush.Muter.io", qos: .userInitiated)
    private let recheckQueue = DispatchQueue(label: "AutoHush.Muter.recheck", qos: .utility)
    private let recheck: TimeInterval
    private let timer = OSAllocatedUnfairLock<DispatchSourceTimer?>(initialState: nil)
    private let failures = OSAllocatedUnfairLock(initialState: false)
    private let logger = AutoHushLogger(category: "AudioMonitor")

    package init(recheckInterval: TimeInterval = ProcessTapMuter.recheckInterval) {
        recheck = recheckInterval
    }

    /// Whether a later look found processes it couldn't mute (they may have
    /// been heard meanwhile).
    package var missedSome: Bool { failures.withLock { $0 } }

    package func mute(appPID: pid_t) -> Bool {
        if taps.withLock({ $0[appPID] }) != nil { return true }
        let owned = OwnedAudioProcesses()
        let processes = owned.objects(ownedBy: appPID)
        guard !processes.isEmpty else { return false }
        let tap: ProcessTap
        do {
            tap = try ProcessTap(processObjectIDs: processes, muted: true, ioQueue: ioQueue)
        } catch {
            logger.error("[mute] couldn’t mute pid \(appPID, privacy: .public): \(error)")
            return false
        }
        let kept = taps.withLock { taps in
            guard taps[appPID] == nil else { return false }
            taps[appPID] = Muted(tap: tap, processes: Set(processes), owned: owned)
            return true
        }
        if !kept { tap.invalidate() } // muted meanwhile
        logger.notice("[mute] muted pid \(appPID, privacy: .public) (\(processes.count, privacy: .public) audio processes)")
        startRechecking()
        return true
    }

    package func unmute(appPID: pid_t) {
        guard let muted = taps.withLock({ $0.removeValue(forKey: appPID) }) else { return }
        muted.tap.invalidate()
        logger.notice("[mute] unmuted pid \(appPID, privacy: .public)")
        if taps.withLock({ $0.isEmpty }) { stopRechecking() }
    }

    private func startRechecking() {
        timer.withLock { timer in
            guard timer == nil else { return }
            let made = DispatchSource.makeTimerSource(queue: recheckQueue)
            made.schedule(deadline: .now() + recheck, repeating: recheck)
            made.setEventHandler { [weak self] in self?.recheckAll() }
            made.resume()
            timer = made
        }
    }

    private func stopRechecking() {
        timer.withLock { timer in
            timer?.cancel()
            timer = nil
        }
    }

    /// Mutes the processes each muted app started since.
    private func recheckAll() {
        for (pid, muted) in taps.withLock({ $0 }) {
            let now = Set(muted.owned.objects(ownedBy: pid))
            guard !now.isEmpty, !now.isSubset(of: muted.processes) else { continue }
            let tap: ProcessTap
            do {
                tap = try ProcessTap(processObjectIDs: Array(now), muted: true, ioQueue: ioQueue)
            } catch {
                failures.withLock { $0 = true }
                logger.error("[mute] couldn’t mute pid \(pid, privacy: .public)’s new audio processes: \(error)")
                continue
            }
            // Only while it's still that mute: unmuted (or muted afresh) meanwhile, the new tap goes.
            let replaced = taps.withLock { taps -> ProcessTap? in
                guard let current = taps[pid], current.tap === muted.tap else { return nil }
                taps[pid] = Muted(tap: tap, processes: now, owned: muted.owned)
                return current.tap
            }
            guard let replaced else {
                tap.invalidate()
                continue
            }
            replaced.invalidate()
            logger.notice("[mute] pid \(pid, privacy: .public) plays from more processes: \(now.count, privacy: .public) muted now")
        }
    }

    deinit {
        timer.withLock { $0?.cancel() }
        taps.withLock { $0.values }.forEach { $0.tap.invalidate() }
    }
}
