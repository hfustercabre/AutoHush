import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

/// Each test has preferences of its own, in memory.
@Suite("SystemVolumeLeveler", .waitsTimeLimit)
final class SystemVolumeLevelerTests {
    private let defaults: UserDefaults = MemoryDefaults()

    private func leveler(_ volume: any SystemVolumeControlling, clock: ManualClock = ManualClock()) -> SystemVolumeLeveler {
        SystemVolumeLeveler(volume: volume, defaults: defaults, now: { clock.now })
    }

    @Test("lowers each channel by as much, never below the lowest, keeps nothing and never raises it: each lowering lowers again from where the volume is")
    func lowersAndLeaves() {
        let volume = MockSystemVolume([1: -12, 2: -14], lowest: -20)
        let clock = ManualClock()
        let leveler = leveler(volume, clock: clock)
        #expect(leveler.lower(by: -4))
        #expect(volume.decibels == [1: -16, 2: -18]) // the balance kept
        #expect(defaults.data(forKey: SystemVolumeLeveler.leftKey) == nil) // nothing kept to put back
        clock.advance(by: 60)
        #expect(leveler.lower(by: -4)) // the next resume's: from where it is now
        #expect(volume.decibels == [1: -20, 2: -20]) // -20 the lowest
        #expect(volume.sets.count == 2) // only lowered, never raised
    }

    @Test("two monitorings resuming for the same quiet moment lower it once: a second lowering within 2 s is taken as done")
    func sameQuietOnce() {
        let volume = MockSystemVolume([0: -10])
        let clock = ManualClock()
        let leveler = leveler(volume, clock: clock)
        #expect(leveler.lower(by: -6))
        clock.advance(by: 1)
        #expect(leveler.lower(by: -6)) // the held player's, for the same quiet: done already
        #expect(volume.decibels == [0: -16] && volume.sets.count == 1)
        clock.advance(by: 2)
        #expect(leveler.lower(by: -6)) // a later quiet's
        #expect(volume.decibels == [0: -22])
    }

    @Test("an output with no volume control is left alone, and so is a lowering by nothing")
    func noControl() {
        let volume = MockSystemVolume(nil)
        #expect(!leveler(volume).lower(by: -8))
        #expect(volume.sets.isEmpty)
        let controlled = MockSystemVolume([0: -10])
        #expect(!leveler(controlled).lower(by: 0))
        #expect(controlled.sets.isEmpty)
    }

    @Test("at launch, what an older version kept to put the volume back is forgotten, and the volume left as it is")
    func forgetsOlderRecord() {
        let volume = MockSystemVolume([0: -16])
        defaults.set(Data("{}".utf8), forKey: SystemVolumeLeveler.leftKey)
        leveler(volume).forgetLeft()
        #expect(defaults.data(forKey: SystemVolumeLeveler.leftKey) == nil)
        #expect(volume.sets.isEmpty)
    }
}
