import Foundation
import AutoHushKit

/// What AutoHush's mute stands for, for an app that can only be muted
/// (`PlayerSetup.Way.mute`), and how the user's own pause and play end it
/// (the user, 2026-10-15). Muted while other apps play, it reads as paused:
/// AutoHush's pause. Once it has stopped playing for `stopTime` (the user
/// paused it: a gap between songs is shorter) and plays again, the user
/// played it to hear it: the mute is lifted and it reads as playing, as a
/// player the user resumes, which AutoHush then leaves alone until the other
/// apps stop. After a sleep (`forget`), the mute is lifted once it stops.
struct MuteState: Sendable, Equatable {
    static let stopTime: TimeInterval = 3

    private(set) var isMuted = false
    private var stoppedSince: Date?
    private var userStopped = false
    private var forgotten = false

    mutating func mute() {
        self = MuteState()
        isMuted = true
    }

    mutating func unmute() {
        self = MuteState()
    }

    /// AutoHush no longer holds the pause the mute stands for (the Mac
    /// slept): it's lifted once the app stops, never while it plays on.
    mutating func forget() {
        if isMuted { forgotten = true }
    }

    /// Its state, from whether it plays now; `unmute` when the mute must be
    /// lifted now.
    mutating func read(playing: Bool, at now: Date) -> (state: PlayerState, unmute: Bool) {
        guard isMuted else { return (playing ? .playing : .paused, false) }
        guard playing else {
            let since = stoppedSince ?? now
            stoppedSince = since
            if now.timeIntervalSince(since) >= Self.stopTime { userStopped = true }
            if forgotten, userStopped {
                unmute()
                return (.paused, true)
            }
            return (.paused, false)
        }
        stoppedSince = nil
        guard userStopped, !forgotten else { return (.paused, false) }
        // The user played it again: theirs to hear.
        unmute()
        return (.playing, true)
    }
}
