import CoreAudio
import Foundation

/// Mutes the Mac's output for a while, then puts it back as it was: Add an
/// App's check, when it can't mute only the app it checks (AntiDot mode, or
/// no Audio Recording; the user, 2026-10-18). An output muted already is
/// left so; one the user unmuted or muted again meanwhile is theirs. Which
/// output it muted is kept in the preferences until it's put back, so the
/// next launch puts it back if AutoHush quit meanwhile (`restoreIfLeft`).
package final class OutputMute {
    static let leftKey = "checkMutedOutput"
    private let outputs: any OutputMuting
    private let defaults: UserDefaults

    package init(outputs: any OutputMuting = CoreAudioOutputMute(), defaults: UserDefaults = .standard) {
        self.outputs = outputs
        self.defaults = defaults
    }

    /// Whether the output sound plays through now can be muted.
    package var canMute: Bool {
        outputs.defaultOutput().flatMap(outputs.isMuted) != nil
    }

    /// Mutes the output sound plays through, unless it's muted already.
    package func mute() {
        guard defaults.string(forKey: Self.leftKey) == nil, let device = outputs.defaultOutput(),
              outputs.isMuted(device) == false, let uid = outputs.uid(of: device) else { return }
        defaults.set(uid, forKey: Self.leftKey)
        outputs.setMuted(true, device)
    }

    /// Unmutes the output it muted, where it is now (the sound may have moved
    /// to another meanwhile), if it's still muted.
    package func restore() {
        guard let uid = defaults.string(forKey: Self.leftKey) else { return }
        defaults.removeObject(forKey: Self.leftKey)
        guard let device = outputs.device(withUID: uid), outputs.isMuted(device) == true else { return }
        outputs.setMuted(false, device)
    }

    /// At launch: an output muted for a check and not put back (AutoHush quit
    /// or crashed during it) is put back.
    package func restoreIfLeft() {
        restore()
    }
}
