import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

/// Each test has preferences of its own, in memory.
@Suite("SystemVolumeLeveler", .waitsTimeLimit)
final class SystemVolumeLevelerTests {
    private let defaults: UserDefaults = MemoryDefaults()

    private func leveler(_ volume: any SystemVolumeControlling) -> SystemVolumeLeveler {
        SystemVolumeLeveler(volume: volume, defaults: defaults)
    }

    @Test("lowers each channel by as much, never below the lowest, keeps nothing and never raises it: each pause's resume lowers again from where the volume is")
    func lowersAndLeaves() {
        let volume = MockSystemVolume([1: -12, 2: -14], lowest: -20)
        let leveler = leveler(volume)
        leveler.lower(by: -4)
        #expect(volume.decibels == [1: -16, 2: -18]) // the balance kept
        #expect(defaults.data(forKey: SystemVolumeLeveler.leftKey) == nil) // nothing kept to put back
        leveler.musicPaused(since: leveler.lowerings)
        leveler.lower(by: -4) // the next pause's resume: from where it is now
        #expect(volume.decibels == [1: -20, 2: -20]) // -20 the lowest
        #expect(volume.sets.count == 2) // only lowered, never raised
    }

    @Test("once per pause: a try again, or another monitoring resuming for the same quiet however much later (a slow player), lowers nothing more until the music pauses again")
    func oncePerPause() {
        let volume = MockSystemVolume([0: -10])
        let leveler = leveler(volume)
        leveler.lower(by: -6) // the chosen player's resume
        leveler.lower(by: -6) // the held player's, seconds later, for the same quiet
        leveler.lower(by: -6) // a try again
        #expect(volume.decibels == [0: -16] && volume.sets.count == 1)
        leveler.musicPaused(since: leveler.lowerings) // another app plays: a pause, by either monitoring
        leveler.lower(by: -6) // a later quiet's
        #expect(volume.decibels == [0: -22])
    }

    @Test("a pause that began before another monitoring lowered it, and ends after, was for that same quiet: the next resume lowers nothing more")
    func slowPauseKeepsItLowered() {
        let volume = MockSystemVolume([0: -10])
        let leveler = leveler(volume)
        let began = leveler.lowerings // the chosen player's pause begins, its press slow
        leveler.lower(by: -6) // the apps stopped meanwhile: the held player resumes
        leveler.musicPaused(since: began) // the slow pause ends
        leveler.lower(by: -6) // and resumes at once, for the same quiet
        #expect(volume.decibels == [0: -16] && volume.sets.count == 1)
    }

    @Test("an output with no volume control is left alone, and so is a lowering by nothing; neither counts as lowered")
    func noControl() {
        let volume = MockSystemVolume(nil)
        leveler(volume).lower(by: -8)
        #expect(volume.sets.isEmpty)
        let controlled = MockSystemVolume([0: -10])
        let level = leveler(controlled)
        level.lower(by: 0)
        #expect(controlled.sets.isEmpty)
        level.lower(by: -3) // still this pause's to lower
        #expect(controlled.decibels == [0: -13])
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
