import CoreAudio
import Foundation

/// Lowers the Mac's volume as the music resumes (Settings → Behavior;
/// `ResumeLevel` says how far), and never raises it again: the volume it
/// set is the user's from then on, kept nowhere and put back never (the
/// user, 2026-11-13: "the previous volume shouldn't be even saved. Once is
/// changed the app should not make any changes"; before, it went back up
/// at the music's next pause, at a quit and at the next launch, and also
/// when the music's monitoring started over while it played).
package protocol ResumeLeveling: AnyObject, Sendable {
    /// Just before the music resumes: lowers the volume by `decibels`
    /// (below 0), nothing playing yet, so it isn't heard, unless it was
    /// lowered already since the music last paused (a try again, or another
    /// monitoring resuming for the same quiet). Nothing happens with no
    /// volume control, or for 0 dB.
    func lower(by decibels: Float)
    /// How many times it has lowered the volume: read as a pause begins,
    /// for `musicPaused(since:)` as it ends.
    var lowerings: Int { get }
    /// The music paused (or was muted in its place), by any monitoring: its
    /// next resume may lower the volume again, unless the volume was lowered
    /// since the pause began (`lowerings` then), by another monitoring's
    /// resume for the quiet the pause was slow to see.
    func musicPaused(since lowerings: Int)
}

/// `ResumeLeveling` through the output's volume (`SystemVolumeControlling`).
/// Nothing happens on an output with no volume control. One for the whole
/// app, so it lowers once per pause of the music: two monitorings resuming
/// for the same quiet (a player held paused, and the chosen one) lower it
/// once, however long either takes to get there (a 2 s window let a slow
/// player lower it twice).
package final class SystemVolumeLeveler: ResumeLeveling, @unchecked Sendable {
    /// Where older versions kept the volume they lowered, to put it
    /// back at the next launch; removed at launch (`forgetLeft`), unused.
    package static let leftKey = "levelLoweredVolume"

    private let volume: any SystemVolumeControlling
    private let defaults: UserDefaults
    /// Lowered since the music last paused (`musicPaused`): a lowering asked
    /// for meanwhile is taken as done.
    private var lowered = false
    private var count = 0
    /// One lowering at a time: two monitorings never read and set it at once.
    private let lock = NSLock()
    private let logger = AutoHushLogger(category: "VolumeLeveler")

    package init(volume: any SystemVolumeControlling = CoreAudioSystemVolume(), defaults: UserDefaults = .standard) {
        self.volume = volume
        self.defaults = defaults
    }

    package func lower(by decibels: Float) {
        lock.withLock {
            guard decibels < 0, !lowered else { return } // nothing to lower, or lowered for this pause already
            guard let device = volume.defaultOutput(), let current = volume.volume(of: device) else {
                logger.info("[level] the output has no volume control: the music resumes as it was")
                return
            }
            // Each control lowered on the output's own scale, and only ever
            // lowered: a target the output translates to more than it has
            // now is left out, whatever it reports (the user, 2026-11-23:
            // "it should never increase the volume, just decrease it").
            // A volume that's no number between 0 and 1 is no volume, and a
            // scale that doesn't bring each one back to itself isn't
            // trusted: nothing is lowered then, so a wrong scale can't take
            // it further down than "Lower by at most" either (1.4.5's
            // review: X-1, C-1, C-4).
            let scalars = current.scalars.filter { $0.value.isFinite && (0...1).contains($0.value) }
            guard !scalars.isEmpty else {
                logger.info("[level] the output’s volume reads as no volume: the music resumes as it was")
                return
            }
            var targets: [AudioObjectPropertyElement: Float] = [:]
            for (element, now) in scalars {
                guard let level = volume.decibels(at: now, element: element, of: device, in: current, tolerance: Self.scaleTolerance),
                      let target = volume.scalar(forDecibels: max(current.lowest, level + decibels), element: element, of: device),
                      target.isFinite else {
                    logger.info(volume.scalar(forDecibels: current.lowest, element: element, of: device) == nil
                        ? "[level] the output doesn’t translate decibels to its volume: the music resumes as it was"
                        : "[level] the output’s volume and its decibels don’t match: the music resumes as it was")
                    return
                }
                if target < now { targets[element] = max(0, target) }
            }
            guard !targets.isEmpty else {
                logger.info("[level] the output’s volume can’t be lowered from where it is: the music resumes as it was")
                return
            }
            // Refused by the output, it wasn't lowered (C-5 of 1.4.5's review).
            guard volume.setScalars(targets, of: device) else {
                logger.info("[level] the output didn’t take the lowered volume: the music resumes as it was")
                return
            }
            lowered = true
            count += 1
            let before = scalars.values.max() ?? 0
            let after = scalars.merging(targets) { $1 }.values.max() ?? 0
            logger.notice("[level] the Mac’s volume lowered \(String(format: "%.1f", decibels), privacy: .public) dB for the music (\(Self.percent(before), privacy: .public) % → \(Self.percent(after), privacy: .public) %), and left so")
        }
    }

    /// How far a volume taken to decibels and back may land from where it
    /// was for the output's scale to be trusted (its steps round it).
    static let scaleTolerance: Float = 0.02

    private static func percent(_ scalar: Float) -> Int {
        Int((min(max(scalar, 0), 1) * 100).rounded())
    }

    package var lowerings: Int {
        lock.withLock { count }
    }

    package func musicPaused(since lowerings: Int) {
        lock.withLock {
            if count == lowerings { lowered = false } // not lowered while it paused
        }
    }

    /// At launch: what an older version kept to put the volume back is
    /// forgotten, the volume left as it is.
    package func forgetLeft() {
        defaults.removeObject(forKey: Self.leftKey)
    }
}
