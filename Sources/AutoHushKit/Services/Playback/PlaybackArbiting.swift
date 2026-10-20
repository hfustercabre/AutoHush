import Foundation

/// Takes AudioMonitor's events. Each call returns promptly: whatever it leads
/// to (a pause with its fade-out) runs on its own, so the next event is never
/// held up by it.
protocol PlaybackArbiting: Actor {
    /// `heardSince`: for a start, when the app was first heard (before it
    /// counted as playing); `nil` when that isn't known.
    func handleSourceChange(sourceID: String, isPlaying: Bool, heardSince: Date?) async
    /// Whether the player's audio currently comes out of this Mac (as opposed
    /// to another device, through the player's own remote playback).
    func handleLocalPlaybackChange(_ isLocal: Bool) async
    /// How long an app must play, at most, before the monitor counts it, as
    /// it judges apps now: longer in AntiDot mode, and while nothing is
    /// measured.
    func handleStartConfirmationChange(_ longest: TimeInterval) async
    /// Whether the app plays with its microphone on: in a call.
    func handleCallChange(sourceID: String, inCall: Bool) async
}
