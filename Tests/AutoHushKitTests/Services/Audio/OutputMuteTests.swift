import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

/// Each test has the outputs and preferences of its own, in memory.
@Suite("OutputMute")
final class OutputMuteTests {
    private let outputs = MockOutputMuting()
    private let defaults: UserDefaults = MemoryDefaults()

    /// An `OutputMute` of these outputs, with this test's preferences: a
    /// new one stands for a new AutoHush.
    private func outputMute(now: @escaping @Sendable () -> Date = Date.init) -> OutputMute {
        OutputMute(outputs: outputs, defaults: defaults, now: now)
    }

    /// An output muted and not put back is kept for the next launch.
    private var isKept: Bool { defaults.object(forKey: OutputMute.leftKey) != nil }

    @Test("it mutes the output sound plays through and puts it back, once")
    func mutesAndRestores() {
        let mute = outputMute()
        #expect(mute.canMute)
        mute.mute()
        #expect(outputs.mutes[7] == true)
        mute.mute() // muted already by it: nothing more
        mute.restore()
        #expect(outputs.mutes[7] == false)
        outputs.mutes[7] = true // the user mutes it afterwards: left so
        mute.restore()
        #expect(outputs.mutes[7] == true)
    }

    @Test("an output muted already is left muted, and one with no mute control can't be muted")
    func leftAsItWas() {
        outputs.mutes[7] = true
        let mute = outputMute()
        mute.mute()
        mute.restore()
        #expect(outputs.mutes[7] == true)
        outputs.current = 9
        #expect(!mute.canMute)
        mute.mute()
        #expect(outputs.mutes[9] == nil)
    }

    @Test("the output it muted is put back even after the sound moved to another, and after AutoHush quit during it")
    func putBackLater() {
        outputs.mutes[9] = false
        do { // the AutoHush that quits or crashes during the check
            let mute = outputMute()
            mute.mute()
            outputs.soundMoves(to: 9) // headphones plugged in meanwhile: muted too
        }
        #expect(outputs.mutes[7] == true && outputs.mutes[9] == true)
        // A new AutoHush (the one that muted it quit or crashed): the next launch puts both back.
        outputMute().restoreIfLeft()
        #expect(outputs.mutes[7] == false && outputs.mutes[9] == false)
        outputMute().restoreIfLeft() // nothing left: nothing changes
        #expect(outputs.mutes[7] == false)
    }

    @Test("sound moving to another output during the check mutes that one too, and both are put back; once it's put back, a move mutes nothing")
    func followsTheSound() {
        outputs.mutes[9] = false // headphones with a mute control
        let mute = outputMute()
        mute.mute()
        #expect(outputs.followerCount == 1)
        outputs.soundMoves(to: 9) // plugged in during the check
        #expect(outputs.mutes == [7: true, 9: true])
        outputs.soundMoves(to: 7) // and out again: muted already
        mute.restore()
        #expect(outputs.mutes == [7: false, 9: false] && !isKept)
        #expect(outputs.followerCount == 0 && outputs.listenerCount(7) == 0 && outputs.listenerCount(9) == 0)

        outputs.soundMoves(to: 9) // after the check
        #expect(outputs.mutes[9] == false)
    }

    @Test("a check that starts on an output it can't mute, or one muted already, still mutes the one sound moves to")
    func followsFromAnyStart() {
        outputs.current = 9 // no mute control
        let mute = outputMute()
        mute.mute()
        outputs.soundMoves(to: 7)
        #expect(outputs.mutes[7] == true)
        mute.restore()
        #expect(outputs.mutes[7] == false)
    }

    @Test("an output the user unmuted during the check is theirs: sound coming back to it doesn't mute it again")
    func unmutedStaysTheUsers() {
        outputs.mutes[9] = false
        let mute = outputMute()
        mute.mute()
        outputs.user(muted: false, 7) // the mute key: they want to hear it
        outputs.soundMoves(to: 9)
        #expect(outputs.mutes[9] == true)
        outputs.soundMoves(to: 7)
        #expect(outputs.mutes[7] == false)
        mute.restore()
        #expect(outputs.mutes == [7: false, 9: false])

        // The next check mutes it again.
        mute.mute()
        #expect(outputs.mutes[7] == true)
        mute.restore()
    }

    @Test("while muted, the output is listened to, and its own mute heard late changes nothing")
    func ownMuteHeardLate() {
        let mute = outputMute()
        mute.mute()
        #expect(outputs.listenerCount(7) == 1)
        outputs.notify(7) // its own mute, heard late
        mute.restore()
        #expect(outputs.mutes[7] == false && outputs.listenerCount(7) == 0)
    }

    @Test("an output the user unmuted while it was muted, even muted again since, is theirs and left as they set it")
    func userChangeWins() {
        let mute = outputMute()
        mute.mute()
        outputs.user(muted: false, 7) // the mute key: unmuted, then muted again
        outputs.user(muted: true, 7)
        mute.restore()
        #expect(outputs.mutes[7] == true && outputs.listenerCount(7) == 0)
        #expect(!isKept)
    }

    @Test("at launch, only an output muted within the hour is put back; one muted longer ago is the user's, and forgotten")
    func onlyRecentAtLaunch() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        outputMute(now: { start }).mute()
        outputMute(now: { start + OutputMute.maxAge - 60 }).restoreIfLeft()
        #expect(outputs.mutes[7] == false)

        outputMute(now: { start }).mute()
        outputMute(now: { start + OutputMute.maxAge + 60 }).restoreIfLeft()
        #expect(outputs.mutes[7] == true)
        #expect(!isKept)
    }

    @Test("an output unplugged before it's put back is kept, and put back once it's there again, at a later check's end or the next launch")
    func unpluggedKept() {
        let mute = outputMute()
        mute.mute()
        outputs.uids[7] = nil // unplugged during the check
        mute.restore()
        #expect(isKept)

        // Another check, through another output, while it's still away.
        outputs.current = 9
        outputs.mutes[9] = false
        mute.mute()
        mute.restore()
        #expect(outputs.mutes[9] == false && isKept)

        outputs.uids[7] = "BuiltInSpeaker" // back, still muted
        outputMute().restoreIfLeft()
        #expect(outputs.mutes[7] == false && !isKept)
    }
}
