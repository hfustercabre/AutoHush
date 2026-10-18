import CoreAudio
import Foundation

/// Lowers the Mac's volume as the music resumes, and puts it back at the
/// music's next pause (Settings → Advanced; `ResumeLevel` says how far).
/// One for the whole app: each lowering has a token of its own, so only
/// the monitoring that lowered it puts it back.
package protocol ResumeLeveling: AnyObject, Sendable {
    /// Just before the music resumes: lowers the volume by `decibels`
    /// (below 0), nothing playing yet, so it isn't heard. Gives the token
    /// that puts it back, or `nil` when it lowered nothing (no volume
    /// control, or lowered already).
    @discardableResult
    func lower(by decibels: Float) -> UUID?
    /// The music pauses again: back up over `duration` (its fade-out), if
    /// it's still lowered as `token` says.
    func restore(over duration: TimeInterval, lowered token: UUID)
    /// At once, before returning, if it's still lowered as `token` says
    /// (the music didn't resume after all, or its monitoring stops).
    func restoreNow(lowered token: UUID)
    /// At once, before returning, whoever lowered it (AutoHush stops, or
    /// the setting is off).
    func restoreNow()
}

/// `ResumeLeveling` through the output's volume (`SystemVolumeControlling`).
/// Nothing happens on an output with no volume control. If the volume was
/// changed meanwhile (the volume keys, another output chosen and changed),
/// the user's wins: it isn't put back, and a glide back up under way stops.
/// One for the whole app, so two monitorings never lower it over each other.
/// What it lowered is kept in the preferences, with when, until it's put
/// back, so the next launch puts it back if AutoHush quit or crashed
/// meanwhile (`restoreIfLeft`), only within `maxAge`. No call waits for the
/// glide back up: a resume or a put-back at once stops it.
package final class SystemVolumeLeveler: ResumeLeveling, @unchecked Sendable {
    /// A change of this much (dB) since AutoHush lowered it is the user's.
    static let ownChangeTolerance: Float = 0.5
    /// How often the volume steps while it's put back.
    static let restoreStep: TimeInterval = 0.05
    /// A volume lowered longer ago than this, and not put back (AutoHush
    /// crashed, or the Mac was shut down), is the user's now: they've heard
    /// it so since. As Add an App's check's mute (`OutputMute.maxAge`).
    static let maxAge: TimeInterval = 60 * 60
    static let leftKey = "levelLoweredVolume"

    /// The output it lowered (by its lasting ID), and each of its volumes
    /// before and after; the lowering's token, and when. Both `nil` in a
    /// record kept before they were (2026-10-18).
    private struct Lowered: Codable {
        let uid: String
        let original: [AudioObjectPropertyElement: Float]
        let lowered: [AudioObjectPropertyElement: Float]
        var token: UUID?
        var at: Date?
    }

    private let volume: any SystemVolumeControlling
    private let defaults: UserDefaults
    private let sleep: @Sendable (TimeInterval) -> Void
    private let now: @Sendable () -> Date
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
                 sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                 now: @escaping @Sendable () -> Date = Date.init) {
        self.volume = volume
        self.defaults = defaults
        self.sleep = sleep
        self.now = now
    }

    @discardableResult
    package func lower(by decibels: Float) -> UUID? {
        lock.withLock {
            guard decibels < 0 else { return nil }
            // Still gliding back up: it's done at once, and lowered again from there.
            if isGliding { putBackNow() }
            guard lowered == nil else { return nil }
            guard let device = volume.defaultOutput(), let uid = volume.uid(of: device),
                  let current = volume.volume(of: device) else {
                logger.info("[level] the output has no volume control: the music resumes as it was")
                return nil
            }
            let target = current.decibels.mapValues { max(current.lowest, $0 + decibels) }
            volume.setDecibels(target, of: device)
            let token = UUID()
            lowered = Lowered(uid: uid, original: current.decibels, lowered: volume.volume(of: device)?.decibels ?? target,
                              token: token, at: now())
            logger.notice("[level] the Mac’s volume lowered \(String(format: "%.1f", decibels), privacy: .public) dB for the music")
            return token
        }
    }

    package func restore(over duration: TimeInterval, lowered token: UUID) {
        lock.withLock {
            guard let lowered, lowered.token == token, !isGliding else { return }
            guard let device = loweredDevice() else {
                self.lowered = nil
                return
            }
            glide += 1
            isGliding = true
            let number = glide
            glideQueue.async { self.glideBack(number, on: device, from: lowered.lowered, over: duration) }
        }
    }

    package func restoreNow(lowered token: UUID) {
        lock.withLock {
            guard lowered?.token == token else { return } // another's, or put back already
            putBackNow()
        }
    }

    package func restoreNow() {
        lock.withLock { putBackNow() }
    }

    /// At launch: a volume lowered for the music and not put back (AutoHush
    /// quit or crashed meanwhile) is put back, unless the user changed it
    /// since, or it was lowered longer ago than `maxAge`.
    package func restoreIfLeft() {
        lock.withLock {
            guard lowered == nil, let data = defaults.data(forKey: Self.leftKey) else { return }
            lowered = try? JSONDecoder().decode(Lowered.self, from: data)
            if let at = lowered?.at, now().timeIntervalSince(at) > Self.maxAge {
                logger.notice("[level] the volume lowered for the music over an hour ago is left as it is")
                lowered = nil
                return
            }
            putBackNow()
        }
    }

    /// Back up in steps over `duration`, from `start`, unless a newer change
    /// stops it, or the volume no longer reads the last step: the user
    /// changed it (or the output is gone), and theirs wins.
    private func glideBack(_ number: Int, on device: AudioObjectID, from start: [AudioObjectPropertyElement: Float],
                           over duration: TimeInterval) {
        let steps = max(1, Int((duration / Self.restoreStep).rounded()))
        var last = start
        for step in 1...steps {
            let goesOn: Bool = lock.withLock {
                guard glide == number, let lowered else { return false }
                guard Self.reads(volume.volume(of: device)?.decibels, as: last) else {
                    logger.notice("[level] the volume was changed meanwhile, or its output is gone: it’s left as it is")
                    isGliding = false
                    self.lowered = nil
                    return false
                }
                let progress = Float(step) / Float(steps)
                let next = lowered.lowered.merging(lowered.original) { from, to in from + (to - from) * progress }
                volume.setDecibels(next, of: device)
                // What the output took (it may round): the next step checks against it.
                last = volume.volume(of: device)?.decibels ?? next
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
              Self.reads(volume.volume(of: device)?.decibels, as: lowered.lowered)
        else {
            logger.notice("[level] the volume was changed meanwhile: it’s left as it is")
            return nil
        }
        return device
    }

    /// Whether the volume read, `now`, is still `expected` on each of its
    /// controls, give or take `ownChangeTolerance`; never for an output gone.
    private static func reads(_ now: [AudioObjectPropertyElement: Float]?,
                              as expected: [AudioObjectPropertyElement: Float]) -> Bool {
        guard let now else { return false }
        return expected.allSatisfy { element, value in now[element].map { abs($0 - value) <= ownChangeTolerance } ?? false }
    }
}
