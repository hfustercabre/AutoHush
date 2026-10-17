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
    /// At once, before returning (AutoHush stops, or the setting is off).
    func restoreNow()
}

/// `ResumeLeveling` through the output's volume (`SystemVolumeControlling`).
/// Nothing happens on an output with no volume control. If the volume was
/// changed meanwhile (the volume keys, another output chosen and changed),
/// the user's wins: it isn't put back.
package final class SystemVolumeLeveler: ResumeLeveling, @unchecked Sendable {
    /// A change of this much (dB) since AutoHush lowered it is the user's.
    static let ownChangeTolerance: Float = 0.5
    /// How often the volume steps while it's put back.
    static let restoreStep: TimeInterval = 0.05

    private struct Lowered {
        let device: AudioObjectID
        let original: [AudioObjectPropertyElement: Float]
        let lowered: [AudioObjectPropertyElement: Float]
    }

    private let volume: any SystemVolumeControlling
    private let sleep: @Sendable (TimeInterval) -> Void
    /// Changes happen in turn: a resume never interleaves with a restore.
    private let queue = DispatchQueue(label: "AutoHush.VolumeLeveler")
    private var lowered: Lowered?
    private let logger = AutoHushLogger(category: "PlaybackArbiter")

    package init(volume: any SystemVolumeControlling = CoreAudioSystemVolume(),
                 sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.volume = volume
        self.sleep = sleep
    }

    package func lower(by decibels: Float) {
        queue.sync {
            guard lowered == nil, decibels < 0 else { return }
            guard let device = volume.defaultOutput(), let current = volume.volume(of: device) else {
                logger.info("[level] the output has no volume control: the music resumes as it was")
                return
            }
            let target = current.decibels.mapValues { max(current.lowest, $0 + decibels) }
            volume.setDecibels(target, of: device)
            lowered = Lowered(device: device, original: current.decibels, lowered: volume.volume(of: device)?.decibels ?? target)
            logger.notice("[level] the Mac's volume lowered \(String(format: "%.1f", decibels), privacy: .public) dB for the music")
        }
    }

    package func restore(over duration: TimeInterval) {
        queue.async { self.putBack(over: duration) }
    }

    package func restoreNow() {
        queue.sync { putBack(over: 0) }
    }

    private func putBack(over duration: TimeInterval) {
        guard let lowered else { return }
        self.lowered = nil
        guard let now = volume.volume(of: lowered.device)?.decibels,
              lowered.lowered.allSatisfy({ element, value in now[element].map { abs($0 - value) <= Self.ownChangeTolerance } ?? false }) else {
            logger.notice("[level] the volume was changed meanwhile: it’s left as it is")
            return
        }
        let steps = max(1, Int((duration / Self.restoreStep).rounded()))
        for step in 1...steps {
            let progress = Float(step) / Float(steps)
            volume.setDecibels(lowered.lowered.merging(lowered.original) { from, to in from + (to - from) * progress },
                               of: lowered.device)
            if step < steps { sleep(Self.restoreStep) }
        }
        logger.notice("[level] the Mac's volume is back")
    }
}
