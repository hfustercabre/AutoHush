import CoreAudio
import Foundation
@testable import AutoHushKit

/// Two outputs, each with its own volume, in memory: the speakers (42) and
/// headphones (43); sound plays through `current`.
final class TwoOutputs: SystemVolumeControlling, @unchecked Sendable {
    // Read and written only under `lock` (`uids` never changes).
    private let lock = NSLock()
    private var _current: AudioObjectID = 42
    private var _decibels: [AudioObjectID: [AudioObjectPropertyElement: Float]] = [42: [0: -10], 43: [0: -20]]
    private var _sets: [(device: AudioObjectID, decibels: [AudioObjectPropertyElement: Float])] = []
    private let uids: [AudioObjectID: String] = [42: "Speakers", 43: "Headphones"]

    var current: AudioObjectID {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }

    var decibels: [AudioObjectID: [AudioObjectPropertyElement: Float]] { lock.withLock { _decibels } }

    /// Each volume set, in turn, with its output.
    var sets: [(device: AudioObjectID, decibels: [AudioObjectPropertyElement: Float])] { lock.withLock { _sets } }

    func defaultOutput() -> AudioObjectID? { current }
    func uid(of device: AudioObjectID) -> String? { uids[device] }
    func device(withUID uid: String) -> AudioObjectID? { uids.first { $0.value == uid }?.key }

    func volume(of device: AudioObjectID) -> SystemVolume? {
        lock.withLock { _decibels[device].map { SystemVolume(decibels: $0, lowest: -60) } }
    }

    func setDecibels(_ decibels: [AudioObjectPropertyElement: Float], of device: AudioObjectID) {
        lock.withLock {
            _decibels[device] = decibels
            _sets.append((device, decibels))
        }
    }
}
