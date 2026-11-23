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

    @Test("an output whose own scale would put the volume up (it reports its level wrongly) is never raised: left as it is, not counted as lowered (the user, 2026-11-23)")
    func neverRaises() {
        let volume = MockSystemVolume([0: -25.6], lowest: -40) // 36 %
        volume.translatesToScalar = { _ in 0.78 } // as 0 dB lowered 8.7 dB came out
        let leveler = leveler(volume)
        leveler.lower(by: -8.7)
        #expect(volume.sets.isEmpty)
        #expect(volume.decibels == [0: -25.6])
        #expect(leveler.lowerings == 0)
    }

    @Test("lowered on the output's own scale: 36 % (-25.6 dB of -40) lowered 8.7 dB is about 14 %, never more than it was")
    func lowersOnItsOwnScale() {
        let volume = MockSystemVolume([1: -25.6, 2: -25.6], lowest: -40)
        leveler(volume).lower(by: -8.7)
        #expect(volume.decibels == [1: -34.3, 2: -34.3])
        #expect(volume.sets.count == 1)
    }

    @Test("lowered on the output's dB-to-volume translation, found again there: a MacBook Pro's speakers (a curve; their volume-to-dB line disagrees) at 60 % lowered 3.3 dB land at about 52 %, not 30 % (C-1 of 1.4.5's review)")
    func lowersOnItsVolumeCurve() throws {
        let volume = MockSystemVolume(nil, lowest: -63.5)
        volume.scalars = [0: 0.6]
        volume.translatesToScalar = { decibels in let x = (decibels + 63.5) / 63.5; return x * x } // as measured, 2026-11-23
        leveler(volume).lower(by: -3.3)
        let after = try #require(volume.scalars?[0])
        #expect(abs(after - 0.522) < 0.005)
    }

    @Test("a scale on which the volume isn't found again (it doesn't hold) lowers nothing, so a wrong scale can't take it further down either")
    func untrustedScaleLowersNothing() {
        let volume = MockSystemVolume([0: -20], lowest: -40) // 50 %
        volume.translatesToScalar = { _ in 0.2 } // every level is 20 %
        let leveler = leveler(volume)
        leveler.lower(by: -6)
        #expect(volume.sets.isEmpty && leveler.lowerings == 0)
    }

    @Test("a volume that's no number between 0 and 1 (a broken driver's) is left out, with no crash; the other channel is lowered (X-1 of 1.4.5's review)")
    func brokenValueLeftOut() throws {
        let volume = MockSystemVolume(nil, lowest: -40)
        volume.scalars = [1: .nan, 2: 0.5]
        leveler(volume).lower(by: -4)
        #expect(volume.sets.count == 1 && volume.sets[0].keys.sorted() == [2])
        #expect(try abs(#require(volume.scalars?[2]) - 0.4) < 0.001)
    }

    @Test("a volume at the bottom of a curve that doesn't reach 0 (its lowest level is 1 %) isn't raised to it: nothing set, not counted (R2 of 1.4.5's fixes' review)")
    func bottomNeverRaised() {
        let volume = MockSystemVolume(nil, lowest: -40)
        volume.scalars = [0: 0]
        volume.translatesToScalar = { max(0.01, 1 + $0 / 40) }
        let leveler = leveler(volume)
        leveler.lower(by: -6)
        #expect(volume.sets.isEmpty && leveler.lowerings == 0)
    }

    @Test("an output with gain above 0 dB, at 100 %, is found at its top and lowered from there (R3 of 1.4.5's fixes' review)")
    func gainAboveZero() throws {
        let volume = MockSystemVolume(nil, lowest: -48, highest: 12)
        volume.scalars = [0: 1]
        volume.translatesToScalar = { ($0 + 48) / 60 }
        leveler(volume).lower(by: -6)
        #expect(try abs(#require(volume.scalars?[0]) - 0.9) < 0.001)
    }

    @Test("an output with no translation but a dB reading (a routing app's virtual device) is lowered through its decibels, checked on its volume after")
    func lowersByDecibelsWithoutTranslation() {
        let volume = MockSystemVolume([0: -40], lowest: -96) // 58 %
        volume.translates = false
        let leveler = leveler(volume)
        leveler.lower(by: -6)
        #expect(volume.decibels == [0: -46] && leveler.lowerings == 1)
    }

    @Test("lowered through a dB reading that turns out wrong (its volume went up), the volume is put back, and not tried again for that pause: never raised (C-2 of 1.4.6's review)")
    func decibelsThatRaiseArePutBack() {
        let volume = MockSystemVolume([0: -25.6], lowest: -40) // 36 %
        volume.translates = false
        volume.decibelsSetTo = { _ in 0.78 } // as the Sony's 0 dB reading did
        let leveler = leveler(volume)
        leveler.lower(by: -8.7)
        #expect(volume.decibels == [0: -25.6])
        let sets = volume.sets.count
        leveler.lower(by: -8.7) // a resume tried again, or another monitoring's for the same quiet
        #expect(volume.sets.count == sets && volume.decibels == [0: -25.6])
    }

    @Test("a dB reading outside the output's own range isn't one, above or below it: nothing set (C-3 of 1.4.6's review)",
          arguments: [Float(12), -120])
    func decibelsOutsideRange(reading: Float) {
        let volume = MockSystemVolume([0: -40], lowest: -96)
        volume.translates = false
        volume.decibelsReadAs = { _ in reading }
        let leveler = leveler(volume)
        leveler.lower(by: -6)
        #expect(volume.sets.isEmpty && leveler.lowerings == 0)
    }

    @Test("a try put back for going up isn't made again that pause, and is at the next (L4 of 1.4.6's fixes' review)")
    func putBackTryAgainAtNextPause() {
        let volume = MockSystemVolume([0: -25.6], lowest: -40)
        volume.translates = false
        volume.decibelsSetTo = { _ in 0.78 }
        let leveler = leveler(volume)
        leveler.lower(by: -8.7)
        #expect(leveler.lowerings == 1)
        let sets = volume.sets.count
        leveler.musicPaused(since: leveler.lowerings) // the next pause
        volume.decibelsSetTo = nil // read right now
        leveler.lower(by: -8.7)
        #expect(volume.sets.count > sets && volume.decibels == [0: -34.3])
    }

    @Test("an output with gain above 0 dB and no translation is lowered through its dB reading, its range's top counted in the bound")
    func decibelsWithGain() {
        let volume = MockSystemVolume([0: -40], lowest: -96, highest: 12)
        volume.translates = false
        leveler(volume).lower(by: -6)
        #expect(volume.decibels == [0: -46])
    }

    @Test("lowered through its decibels, a volume that didn't go down, or went further down than its range allows (a reading too low), is put back; one too far isn't tried again that pause, one unchanged or refused may be")
    func decibelsReadBackChecks() {
        // Unchanged; 5 % for -6 dB (past twice 6 dB straight across 96); refused.
        for (setTo, refused, tries) in [(Float(1) - 40 / 96, false, 0), (Float(0.05), false, 1), (Float(0.4), true, 0)] {
            let volume = MockSystemVolume([0: -40], lowest: -96) // 58 %
            volume.translates = false
            volume.decibelsSetTo = { _ in setTo }
            volume.takesDecibelSets = !refused
            let leveler = leveler(volume)
            leveler.lower(by: -6)
            #expect(volume.decibels == [0: -40] && leveler.lowerings == tries)
        }
    }

    @Test("an output with neither a translation nor a dB reading is left alone")
    func noTranslationNoDecibels() {
        let volume = MockSystemVolume([0: -10], lowest: -64)
        volume.translates = false
        volume.readsDecibels = false
        let leveler = leveler(volume)
        leveler.lower(by: -6)
        #expect(volume.sets.isEmpty && leveler.lowerings == 0)
    }

    @Test("a lowering the output refuses isn't counted: the next resume of the pause may lower it (C-5 of 1.4.5's review)")
    func refusedNotCounted() {
        let volume = MockSystemVolume([0: -10])
        volume.takesSets = false
        let leveler = leveler(volume)
        leveler.lower(by: -6)
        #expect(leveler.lowerings == 0)
        volume.takesSets = true
        leveler.lower(by: -6)
        #expect(volume.decibels == [0: -16] && leveler.lowerings == 1)
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
