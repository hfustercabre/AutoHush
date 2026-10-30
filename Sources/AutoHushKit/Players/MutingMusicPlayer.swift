import Foundation

/// A player that mutes itself when it refuses to pause (see `AudioMuting`),
/// through Core Audio's process taps on its own sound, which may also tell
/// whether it can be heard.
package protocol MutingMusicPlayer: MusicPlayer {
    /// Whether it may tap its sound: not in AntiDot mode, which promises no
    /// audio taps. Without taps it doesn't mute.
    func allowTaps(_ allowed: Bool)
    /// For a player that says it isn't playing while it can be heard (a web
    /// app during an ad its site won't pause): mutes it until it's played
    /// again, as for a refused pause. `false` when it's silent, or muting
    /// isn't possible or allowed.
    func muteIfPlayingAnyway() async -> Bool
    /// AutoHush no longer holds the pause a mute stands in for (the Mac
    /// slept): the player is paused for real as soon as it can be, and the
    /// mute lifted then, or once it's silent. It isn't played again.
    func forgetPause() async
    /// Lifts a mute `muteIfPlayingAnyway` left, without playing anything:
    /// once AutoHush no longer watches it (its monitoring stopped).
    func releaseMute() async
    /// Whether its pause is a mute of its own now (a web page during an ad
    /// its site won't pause): AutoHush leaves it to that mute.
    func isMutedForPause() async -> Bool
}

extension MutingMusicPlayer {
    package func isMutedForPause() async -> Bool { false }
}
