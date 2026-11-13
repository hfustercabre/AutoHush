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
    /// (below 0), nothing playing yet, so it isn't heard. Whether it's
    /// lowered for the music (also when another monitoring lowered it for
    /// the same quiet just before); `false`: no volume control, or nothing
    /// to lower.
    @discardableResult
    func lower(by decibels: Float) -> Bool
}

/// `ResumeLeveling` through the output's volume (`SystemVolumeControlling`).
/// Nothing happens on an output with no volume control. One for the whole
/// app: two monitorings resuming for the same quiet moment (a player held
/// paused, and the chosen one) lower it once (`sameQuiet`).
package final class SystemVolumeLeveler: ResumeLeveling, @unchecked Sendable {
    /// Where older versions kept the volume they lowered, to put it
    /// back at the next launch; removed at launch (`forgetLeft`), unused.
    package static let leftKey = "levelLoweredVolume"
    /// A lowering this soon after the last is for the same quiet moment,
    /// asked by another monitoring: taken as done, not lowered twice.
    static let sameQuiet: TimeInterval = 2

    private let volume: any SystemVolumeControlling
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    /// When it last lowered it (`sameQuiet`).
    private var loweredAt: Date?
    /// One lowering at a time: two monitorings never read and set it at once.
    private let lock = NSLock()
    private let logger = AutoHushLogger(category: "VolumeLeveler")

    package init(volume: any SystemVolumeControlling = CoreAudioSystemVolume(), defaults: UserDefaults = .standard,
                 now: @escaping @Sendable () -> Date = Date.init) {
        self.volume = volume
        self.defaults = defaults
        self.now = now
    }

    @discardableResult
    package func lower(by decibels: Float) -> Bool {
        lock.withLock {
            guard decibels < 0 else { return false }
            if let loweredAt, now().timeIntervalSince(loweredAt) < Self.sameQuiet { return true } // lowered for this quiet already
            guard let device = volume.defaultOutput(), let current = volume.volume(of: device) else {
                logger.info("[level] the output has no volume control: the music resumes as it was")
                return false
            }
            let target = current.decibels.mapValues { max(current.lowest, $0 + decibels) }
            volume.setDecibels(target, of: device)
            loweredAt = now()
            logger.notice("[level] the Mac’s volume lowered \(String(format: "%.1f", decibels), privacy: .public) dB for the music, and left so")
            return true
        }
    }

    /// At launch: what an older version kept to put the volume back is
    /// forgotten, the volume left as it is.
    package func forgetLeft() {
        defaults.removeObject(forKey: Self.leftKey)
    }
}
