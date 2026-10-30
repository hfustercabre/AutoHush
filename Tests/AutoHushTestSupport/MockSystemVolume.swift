import CoreAudio
import Foundation
import AutoHushKit

// Stand-ins for the Mac's outputs: their mutes (Add an App's check) and
// their volume (Level the volume). Shared by the engine's tests and the
// app's (AppDelegate), so no test mutes or turns down the machine it runs on.

/// An output whose volume is per channel (or main), or none, in memory:
/// sound plays through 42 ("Speakers"), unless it's unplugged.
package final class MockSystemVolume: SystemVolumeControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var _decibels: [AudioObjectPropertyElement: Float]?
    private var _sets: [[AudioObjectPropertyElement: Float]] = []
    private var _isPlugged = true
    package let lowest: Float

    package init(_ decibels: [AudioObjectPropertyElement: Float]?, lowest: Float = -60) {
        _decibels = decibels
        self.lowest = lowest
    }

    package var decibels: [AudioObjectPropertyElement: Float]? {
        get { lock.withLock { _decibels } }
        set { lock.withLock { _decibels = newValue } }
    }

    /// Each volume set, in turn.
    package var sets: [[AudioObjectPropertyElement: Float]] { lock.withLock { _sets } }

    package var isPlugged: Bool {
        get { lock.withLock { _isPlugged } }
        set { lock.withLock { _isPlugged = newValue } }
    }

    package func defaultOutput() -> AudioObjectID? { isPlugged ? 42 : nil }
    package func uid(of device: AudioObjectID) -> String? { device == 42 && isPlugged ? "Speakers" : nil }
    package func device(withUID uid: String) -> AudioObjectID? { uid == "Speakers" && isPlugged ? 42 : nil }

    package func volume(of device: AudioObjectID) -> SystemVolume? {
        guard device == 42, isPlugged else { return nil }
        return decibels.map { SystemVolume(decibels: $0, lowest: lowest) }
    }

    package func setDecibels(_ decibels: [AudioObjectPropertyElement: Float], of device: AudioObjectID) {
        lock.withLock {
            _decibels = decibels
            _sets.append(decibels)
        }
    }
}
