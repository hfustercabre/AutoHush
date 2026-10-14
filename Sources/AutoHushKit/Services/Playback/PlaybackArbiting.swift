import Foundation
import OSLog

/// Takes AudioMonitor's events. Each call returns promptly: whatever it leads
/// to (a pause with its fade-out) runs on its own, so the next event is never
/// held up by it.
package protocol PlaybackArbiting: Actor {
    /// `heardSince`: for a start, when the app was first heard (before it
    /// counted as playing); `nil` when that isn't known.
    func handleSourceChange(sourceID: String, isPlaying: Bool, heardSince: Date?) async
    /// Whether the player's audio currently comes out of this Mac (as opposed
    /// to another device, e.g. through Spotify Connect).
    func handleLocalPlaybackChange(_ isLocal: Bool) async
}
