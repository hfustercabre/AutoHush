import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit

@Suite("SystemVolumeLeveler")
struct SystemVolumeLevelerTests {
    /// An output whose volume is per channel, or none.
    private final class FakeVolume: SystemVolumeControlling, @unchecked Sendable {
        private let lock = NSLock()
        private var _decibels: [AudioObjectPropertyElement: Float]?
        private var _sets: [[AudioObjectPropertyElement: Float]] = []
        let lowest: Float

        init(_ decibels: [AudioObjectPropertyElement: Float]?, lowest: Float = -60) {
            _decibels = decibels
            self.lowest = lowest
        }

        var decibels: [AudioObjectPropertyElement: Float]? {
            get { lock.withLock { _decibels } }
            set { lock.withLock { _decibels = newValue } }
        }
        var sets: [[AudioObjectPropertyElement: Float]] { lock.withLock { _sets } }

        func defaultOutput() -> AudioObjectID? { 42 }
        func volume(of device: AudioObjectID) -> SystemVolume? {
            decibels.map { SystemVolume(decibels: $0, lowest: lowest) }
        }
        func setDecibels(_ decibels: [AudioObjectPropertyElement: Float], of device: AudioObjectID) {
            lock.withLock {
                _decibels = decibels
                _sets.append(decibels)
            }
        }
    }

    @Test("lowers each channel by as much, never below the lowest, and puts it back over the fade-out in steps")
    func lowersAndRestores() {
        let volume = FakeVolume([1: -12, 2: -14], lowest: -20)
        let leveler = SystemVolumeLeveler(volume: volume, sleep: { _ in })
        leveler.lower(by: -6)
        #expect(volume.decibels == [1: -18, 2: -20]) // the balance kept, -20 the lowest
        leveler.lower(by: -3) // already lowered: once only
        #expect(volume.decibels == [1: -18, 2: -20])

        leveler.restore(over: 0.2)
        leveler.restoreNow() // waits for the restore
        #expect(volume.decibels == [1: -12, 2: -14])
        #expect(volume.sets.count == 1 + 4) // lowered, then 4 steps of 50 ms
        #expect(volume.sets[1] == [1: -16.5, 2: -18.5])
    }

    @Test("the user's own change wins: a volume changed meanwhile is left as it is")
    func userChangeWins() {
        let volume = FakeVolume([0: -10])
        let leveler = SystemVolumeLeveler(volume: volume, sleep: { _ in })
        leveler.lower(by: -8)
        volume.decibels = [0: -25] // the volume keys
        leveler.restoreNow()
        #expect(volume.decibels == [0: -25])
    }

    @Test("an output with no volume control is left alone, and so is a restore with nothing lowered")
    func noControl() {
        let volume = FakeVolume(nil)
        let leveler = SystemVolumeLeveler(volume: volume, sleep: { _ in })
        leveler.lower(by: -8)
        leveler.restoreNow()
        #expect(volume.sets.isEmpty)
    }
}
