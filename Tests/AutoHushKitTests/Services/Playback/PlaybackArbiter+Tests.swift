import Foundation
@testable import AutoHushKit

// PlaybackArbiter: what its tests drive it with.
extension PlaybackArbiter {
    /// Reports a source change, then waits for the pause it may start, so a
    /// test sees its outcome.
    func sourceChanged(_ sourceID: String, playing: Bool, heardSince: Date? = nil) async {
        await handleSourceChange(sourceID: sourceID, isPlaying: playing, heardSince: heardSince)
        await waitForPause()
    }
}
