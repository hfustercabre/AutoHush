import CoreAudio
import Foundation

/// Mutes the Mac's output for a while, then puts it back as it was: Add an
/// App's check, when it can't mute only the app it checks (AntiDot mode, or
/// no Audio Recording; the user, 2026-10-18). An output muted already is
/// left so. Sound moving to another output meanwhile (headphones plugged
/// in) is followed: that one is muted too. Each output it muted is listened
/// to until it's put back: once the user unmutes it, it's theirs, and left
/// as they set it. Each output it muted is kept in the preferences, with
/// when, until it's put back, so the next launch puts it back if AutoHush
/// quit meanwhile (`restoreIfLeft`), and one unplugged meanwhile is put back
/// once it's there again; only within `maxAge`, after which its mute is the
/// user's.
package final class OutputMute: @unchecked Sendable {
    static let leftKey = "checkMutedOutput"
    /// A check takes minutes: an output muted longer ago than this, and not
    /// put back (AutoHush crashed, the output unplugged), is the user's now.
    static let maxAge: TimeInterval = 60 * 60
    private let outputs: any OutputMuting
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    /// Guards the record, what follows (the listeners' calls come from a
    /// queue of their own) and the listeners.
    private let lock = NSLock()
    /// Between `mute()` and `restore()`: an output sound moves to is muted too.
    private var isMuting = false
    /// The outputs the user unmuted meanwhile: theirs, never muted again
    /// until it's put back, should sound come back to them.
    private var unmutedByUser: Set<String> = []
    /// Listen to sound moving to another output, and to each output it
    /// muted, until it's put back.
    private var listeners: [AnyObject] = []

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

    /// Mutes the output sound plays through, unless it's muted already, and
    /// any it moves to until `restore()`.
    package func mute() {
        // Listened to first, so sound moving meanwhile isn't missed.
        let following = lock.withLock { isMuting } ? nil : outputs.observeDefaultOutput { [weak self] in self?.outputChanged() }
        lock.withLock {
            isMuting = true
            if let following { listeners.append(following) }
            muteOutputInUse()
        }
    }

    /// Unmutes the outputs it muted, where they are now (the sound may have
    /// moved to another meanwhile), if they're still muted. One that's gone
    /// (unplugged) is kept, for the next time.
    package func restore() {
        let listening = lock.withLock {
            isMuting = false // nothing more is muted from now on
            defer { listeners = [] }
            return listeners
        }
        letGo(listening)
        lock.withLock {
            unmutedByUser = []
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

    /// Under the lock: mutes the output sound plays through now, unless it's
    /// muted already, can't be, or the user unmuted it meanwhile; and
    /// listens to it.
    private func muteOutputInUse() {
        guard let device = outputs.defaultOutput(), outputs.isMuted(device) == false,
              let uid = outputs.uid(of: device), !unmutedByUser.contains(uid) else { return }
        left[uid] = now()
        outputs.setMuted(true, device)
        if let listener = outputs.observeMute(of: device, { [weak self] in self?.muteChanged(uid, device) }) {
            listeners.append(listener)
        }
    }

    /// Sound moved to another output (headphones plugged in, another chosen)
    /// while it mutes: that one is muted too.
    private func outputChanged() {
        lock.withLock {
            guard isMuting else { return }
            muteOutputInUse()
        }
    }

    /// An output it muted changed: unmuted, it's the user's from then on
    /// (AutoHush only mutes it meanwhile).
    private func muteChanged(_ uid: String, _ device: AudioObjectID) {
        guard outputs.isMuted(device) == false else { return }
        lock.withLock {
            left[uid] = nil
            if isMuting { unmutedByUser.insert(uid) }
        }
    }

    /// Lets go of `listening` outside the lock: letting go may wait for a
    /// call under way, which takes it.
    private func letGo(_ listening: [AnyObject]) {
        withExtendedLifetime(listening) {}
    }
}
