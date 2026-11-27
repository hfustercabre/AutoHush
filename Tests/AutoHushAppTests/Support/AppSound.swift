import Foundation
import AutoHushKit
import AutoHushTestSupport

/// What the user hears of the player's app, for the tests of a pause held
/// by a mute and taken back: its music plays on (its pause is refused, or
/// it's only ever muted), heard unless a tap on it mutes it. Each tap is its
/// own (`tap()`), as `ProcessTapMuter` keeps one per instance, so two can
/// mute the app at once. Every change of whether it's heard is kept, with
/// whether the test's video played then.
final class AppSound: Sendable {
    /// The app became heard, or silent.
    struct Change: Equatable, Sendable, CustomStringConvertible {
        let heard: Bool
        let videoPlays: Bool

        var description: String { "\(heard ? "heard" : "muted")\(videoPlays ? " over the video" : "")" }
    }

    private struct State {
        var muting: Set<Int> = []
        var taps = 0
        var videoPlays = false
        var changes: [Change] = []
    }

    private let state = Locked(State())

    /// A tap on it does mute it now.
    var isMuted: Bool { !state.value.muting.isEmpty }
    var changes: [Change] { state.value.changes }

    /// Heard while the video played, once it had been muted for it: what
    /// taking the pause back must never do.
    var heardOverVideo: [Change] {
        let changes = changes
        guard let muted = changes.firstIndex(where: { !$0.heard }) else { return [] }
        return changes[muted...].filter { $0.heard && $0.videoPlays }
    }

    /// How many times it became heard again once the video had stopped.
    var heardAfterVideo: Int { changes.filter { $0.heard && !$0.videoPlays }.count }

    /// The test's video plays now.
    var videoPlays: Bool { state.value.videoPlays }

    func setVideoPlays(_ plays: Bool) { state.withLock { $0.videoPlays = plays } }

    /// A new tap on its sound.
    func tap() -> SoundTap {
        SoundTap(sound: self, id: state.withLock { state in
            state.taps += 1
            return state.taps
        })
    }

    fileprivate func set(_ tap: Int, muting: Bool) {
        state.withLock { state in
            let wasMuted = !state.muting.isEmpty
            if muting { state.muting.insert(tap) } else { state.muting.remove(tap) }
            let isMuted = !state.muting.isEmpty
            if isMuted != wasMuted { state.changes.append(Change(heard: !isMuted, videoPlays: state.videoPlays)) }
        }
    }

    fileprivate func mutes(_ tap: Int) -> Bool { state.value.muting.contains(tap) }
}

/// One tap on the app's sound (`AudioMuting`), as a `ProcessTapMuter`
/// instance: it mutes the app until it's lifted, whatever other taps do.
final class SoundTap: AudioMuting {
    private let sound: AppSound
    private let id: Int

    fileprivate init(sound: AppSound, id: Int) {
        self.sound = sound
        self.id = id
    }

    /// This tap mutes the app now.
    var isMuting: Bool { sound.mutes(id) }

    func mute(appPID: pid_t) -> Bool {
        sound.set(id, muting: true)
        return true
    }

    func unmute(appPID: pid_t) {
        sound.set(id, muting: false)
    }
}
