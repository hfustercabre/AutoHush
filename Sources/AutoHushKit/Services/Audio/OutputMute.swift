import CoreAudio
import Foundation

/// Mutes the Mac's output for a while, then puts it back as it was: Add an
/// App's check, when it can't mute only the app it checks (AntiDot mode, or
/// no Audio Recording; the user, 2026-10-18). An output muted already is
/// left so. The output it muted is listened to until it's put back: once
/// the user unmutes it, it's theirs, and left as they set it. Each output it
/// muted is kept in the preferences, with when, until it's put back, so the
/// next launch puts it back if AutoHush quit meanwhile (`restoreIfLeft`),
/// and one unplugged meanwhile is put back once it's there again; only
/// within `maxAge`, after which its mute is the user's.
package final class OutputMute: @unchecked Sendable {
    static let leftKey = "checkMutedOutput"
    /// A check takes minutes: an output muted longer ago than this, and not
    /// put back (AutoHush crashed, the output unplugged), is the user's now.
    static let maxAge: TimeInterval = 60 * 60
    private let outputs: any OutputMuting
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    /// Guards the record (the listener's calls come from a queue of its own)
    /// and the listener.
    private let lock = NSLock()
    /// Listens to the output it muted, until it's put back.
    private var listener: AnyObject?

    package init(outputs: any OutputMuting = CoreAudioOutputMute(), defaults: UserDefaults = .standard,
                 now: @escaping @Sendable () -> Date = Date.init) {
        self.outputs = outputs
        self.defaults = defaults
        self.now = now
    }

    /// Whether the output sound plays through now can be muted.
    package var canMute: Bool {
        outputs.defaultOutput().flatMap(outputs.isMuted) != nil
    }

    /// The outputs it muted and hasn't put back, by UID, with when.
    private var left: [String: Date] {
        get { defaults.dictionary(forKey: Self.leftKey) as? [String: Date] ?? [:] }
        set {
            if newValue.isEmpty { defaults.removeObject(forKey: Self.leftKey) } else { defaults.set(newValue, forKey: Self.leftKey) }
        }
    }

    /// Mutes the output sound plays through, unless it's muted already.
    package func mute() {
        guard let device = outputs.defaultOutput(), outputs.isMuted(device) == false,
              let uid = outputs.uid(of: device) else { return }
        lock.withLock { left[uid] = now() }
        outputs.setMuted(true, device)
        listen(outputs.observeMute(of: device) { [weak self] in self?.muteChanged(uid, device) })
    }

    /// Unmutes the outputs it muted, where they are now (the sound may have
    /// moved to another meanwhile), if they're still muted. One that's gone
    /// (unplugged) is kept, for the next time.
    package func restore() {
        listen(nil)
        lock.withLock {
            let oldest = now().addingTimeInterval(-Self.maxAge)
            var records = left
            for (uid, mutedAt) in records {
                if mutedAt >= oldest {
                    guard let device = outputs.device(withUID: uid) else { continue }
                    if outputs.isMuted(device) == true { outputs.setMuted(false, device) }
                }
                records[uid] = nil
            }
            left = records
        }
    }

    /// At launch: an output muted for a check and not put back (AutoHush quit
    /// or crashed during it) is put back.
    package func restoreIfLeft() {
        restore()
    }

    /// The output it muted changed: unmuted, it's the user's from then on
    /// (AutoHush only mutes it meanwhile).
    private func muteChanged(_ uid: String, _ device: AudioObjectID) {
        guard outputs.isMuted(device) == false else { return }
        lock.withLock { left[uid] = nil }
    }

    /// Listens with `new` from now on. The old listener is let go outside
    /// the lock: letting go may wait for its call under way, which takes it.
    private func listen(_ new: AnyObject?) {
        let old = lock.withLock {
            defer { listener = new }
            return listener
        }
        withExtendedLifetime(old) {}
    }
}
