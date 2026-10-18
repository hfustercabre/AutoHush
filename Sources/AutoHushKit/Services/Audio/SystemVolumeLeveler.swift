import CoreAudio
import Foundation

/// Lowers the Mac's volume as the music resumes, and puts it back at the
/// music's next pause (Settings → Advanced; `ResumeLevel` says how far).
package protocol ResumeLeveling: AnyObject, Sendable {
    /// Just before the music resumes: lowers the volume by `decibels`
    /// (below 0), nothing playing yet, so it isn't heard.
    func lower(by decibels: Float)
    /// The music pauses again: back up over `duration` (its fade-out).
    func restore(over duration: TimeInterval)
    /// At once, before returning (AutoHush stops, the setting is off, or the
    /// music didn't resume after all).
    func restoreNow()
}

/// `ResumeLeveling` through the output's volume (`SystemVolumeControlling`).
/// Nothing happens on an output with no volume control. If the volume was
/// changed meanwhile (the volume keys, another output chosen and changed),
/// the user's wins: it isn't put back. One for the whole app, so two
/// monitorings never lower it over each other. What it lowered is kept in
/// the preferences until it's put back, so the next launch puts it back if
/// AutoHush quit or crashed meanwhile (`restoreIfLeft`). No call waits for
/// the glide back up: a resume or a put-back at once stops it.
package final class SystemVolumeLeveler: ResumeLeveling, @unchecked Sendable {
    /// A change of this much (dB) since AutoHush lowered it is the user's.
    static let ownChangeTolerance: Float = 0.5
    /// How often the volume steps while it's put back.
    static let restoreStep: TimeInterval = 0.05
    static let leftKey = "levelLoweredVolume"

    /// The output it lowered (by its lasting ID), and each of its volumes
    /// before and after.
    private struct Lowered: Codable {
        let uid: String
        let original: [AudioObjectPropertyElement: Float]
        let lowered: [AudioObjectPropertyElement: Float]
    }

    private let volume: any SystemVolumeControlling
    private let defaults: UserDefaults
    private let sleep: @Sendable (TimeInterval) -> Void
    /// Changes happen in turn: a resume never interleaves with a restore.
    /// Held only while the volume is read or set, never while the glide
    /// waits for its next step.
    private let lock = NSLock()
    /// Where the glide back up steps.
    private let glideQueue = DispatchQueue(label: "AutoHush.VolumeLeveler")
    /// What it lowered and hasn't put back; kept in the preferences too.
    private var lowered: Lowered? {
        didSet {
            if let lowered, let data = try? JSONEncoder().encode(lowered) {
                defaults.set(data, forKey: Self.leftKey)
            } else {
                defaults.removeObject(forKey: Self.leftKey)
            }
        }
    }
    /// Numbers each glide back up: one that's no longer the latest stops.
    private var glide = 0
    private var isGliding = false
    private let logger = AutoHushLogger(category: "PlaybackArbiter")

    package init(volume: any SystemVolumeControlling = CoreAudioSystemVolume(), defaults: UserDefaults = .standard,
                 sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.volume = volume
        self.defaults = defaults
        self.sleep = sleep
    }

    package func lower(by decibels: Float) {
        lock.withLock {
            guard decibels < 0 else { return }
            // Still gliding back up: it's done at once, and lowered again from there.
            if isGliding { putBackNow() }
            guard lowered == nil else { return }
            guard let device = volume.defaultOutput(), let uid = volume.uid(of: device),
                  let current = volume.volume(of: device) else {
                logger.info("[level] the output has no volume control: the music resumes as it was")
                return
            }
            let target = current.decibels.mapValues { max(current.lowest, $0 + decibels) }
            volume.setDecibels(target, of: device)
            lowered = Lowered(uid: uid, original: current.decibels, lowered: volume.volume(of: device)?.decibels ?? target)
            logger.notice("[level] the Mac’s volume lowered \(String(format: "%.1f", decibels), privacy: .public) dB for the music")
        }
    }

    package func restore(over duration: TimeInterval) {
        lock.withLock {
            guard lowered != nil, !isGliding else { return }
            guard let device = loweredDevice() else {
                lowered = nil
                return
            }
            glide += 1
            isGliding = true
            let number = glide
            glideQueue.async { self.glideBack(number, on: device, over: duration) }
        }
    }

    package func restoreNow() {
        lock.withLock { putBackNow() }
    }

    /// At launch: a volume lowered for the music and not put back (AutoHush
    /// quit or crashed meanwhile) is put back, unless the user changed it
    /// since.
    package func restoreIfLeft() {
        lock.withLock {
            guard lowered == nil, let data = defaults.data(forKey: Self.leftKey) else { return }
            lowered = try? JSONDecoder().decode(Lowered.self, from: data)
            putBackNow()
        }
    }

    /// Back up in steps over `duration`, unless a newer change stops it.
    private func glideBack(_ number: Int, on device: AudioObjectID, over duration: TimeInterval) {
        let steps = max(1, Int((duration / Self.restoreStep).rounded()))
        for step in 1...steps {
            let goesOn: Bool = lock.withLock {
                guard glide == number, let lowered else { return false }
                let progress = Float(step) / Float(steps)
                volume.setDecibels(lowered.lowered.merging(lowered.original) { from, to in from + (to - from) * progress }, of: device)
                guard step == steps else { return true }
                isGliding = false
                self.lowered = nil
                logger.notice("[level] the Mac’s volume is back")
                return false
            }
            guard goesOn else { return }
            sleep(Self.restoreStep)
        }
    }

    /// Puts the volume back at once, under the lock: from where a glide back
    /// up reached, or from what it was lowered to.
    private func putBackNow() {
        guard let lowered else { return }
        if isGliding {
            glide += 1 // stops it
            isGliding = false
            if let device = volume.device(withUID: lowered.uid) { volume.setDecibels(lowered.original, of: device) }
        } else if let device = loweredDevice() {
            volume.setDecibels(lowered.original, of: device)
            logger.notice("[level] the Mac’s volume is back")
        }
        self.lowered = nil
    }

    /// The output it lowered, while its volume still reads what it was
    /// lowered to; `nil` once it's gone or the user changed it.
    private func loweredDevice() -> AudioObjectID? {
        guard let lowered, let device = volume.device(withUID: lowered.uid),
              let now = volume.volume(of: device)?.decibels,
              lowered.lowered.allSatisfy({ element, value in now[element].map { abs($0 - value) <= Self.ownChangeTolerance } ?? false })
        else {
            logger.notice("[level] the volume was changed meanwhile: it’s left as it is")
            return nil
        }
        return device
    }
}
