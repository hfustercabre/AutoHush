import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("OutputMute")
struct OutputMuteTests {
    @Test("it mutes the output sound plays through and puts it back, once")
    func mutesAndRestores() {
        let outputs = MockOutputMuting(), suite = TestDefaults("OutputMuteTests"), defaults = suite.defaults
        defer { suite.remove() }
        let mute = OutputMute(outputs: outputs, defaults: defaults)
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
        let outputs = MockOutputMuting(), suite = TestDefaults("OutputMuteTests"), defaults = suite.defaults
        defer { suite.remove() }
        outputs.mutes[7] = true
        let mute = OutputMute(outputs: outputs, defaults: defaults)
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
        let outputs = MockOutputMuting(), suite = TestDefaults("OutputMuteTests"), defaults = suite.defaults
        defer { suite.remove() }
        outputs.mutes[9] = false
        OutputMute(outputs: outputs, defaults: defaults).mute()
        outputs.current = 9 // headphones plugged in meanwhile
        #expect(outputs.mutes[7] == true)
        // A new AutoHush (the one that muted it quit or crashed): the next launch puts it back.
        OutputMute(outputs: outputs, defaults: defaults).restoreIfLeft()
        #expect(outputs.mutes[7] == false && outputs.mutes[9] == false)
        OutputMute(outputs: outputs, defaults: defaults).restoreIfLeft() // nothing left: nothing changes
        #expect(outputs.mutes[7] == false)
    }

    @Test("while muted, the output is listened to: unmuted by the user, even muted again since, it's theirs and left as they set it; its own mute heard late changes nothing")
    func userChangeWins() {
        let outputs = MockOutputMuting(), suite = TestDefaults("OutputMuteTests"), defaults = suite.defaults
        defer { suite.remove() }
        let mute = OutputMute(outputs: outputs, defaults: defaults)
        mute.mute()
        #expect(outputs.listenerCount(7) == 1)
        outputs.notify(7) // its own mute, heard late
        mute.restore()
        #expect(outputs.mutes[7] == false && outputs.listenerCount(7) == 0)

        mute.mute()
        outputs.user(muted: false, 7) // the mute key: unmuted, then muted again
        outputs.user(muted: true, 7)
        mute.restore()
        #expect(outputs.mutes[7] == true && outputs.listenerCount(7) == 0)
        #expect(defaults.object(forKey: OutputMute.leftKey) == nil)
    }

    @Test("at launch, only an output muted within the hour is put back; one muted longer ago is the user's, and forgotten")
    func onlyRecentAtLaunch() {
        let outputs = MockOutputMuting(), suite = TestDefaults("OutputMuteTests"), defaults = suite.defaults
        defer { suite.remove() }
        let start = Date(timeIntervalSince1970: 1_000_000)
        OutputMute(outputs: outputs, defaults: defaults, now: { start }).mute()
        OutputMute(outputs: outputs, defaults: defaults, now: { start + OutputMute.maxAge - 60 }).restoreIfLeft()
        #expect(outputs.mutes[7] == false)

        OutputMute(outputs: outputs, defaults: defaults, now: { start }).mute()
        OutputMute(outputs: outputs, defaults: defaults, now: { start + OutputMute.maxAge + 60 }).restoreIfLeft()
        #expect(outputs.mutes[7] == true)
        #expect(defaults.object(forKey: OutputMute.leftKey) == nil)
    }

    @Test("an output unplugged before it's put back is kept, and put back once it's there again, at a later check's end or the next launch")
    func unpluggedKept() {
        let outputs = MockOutputMuting(), suite = TestDefaults("OutputMuteTests"), defaults = suite.defaults
        defer { suite.remove() }
        let mute = OutputMute(outputs: outputs, defaults: defaults)
        mute.mute()
        outputs.uids[7] = nil // unplugged during the check
        mute.restore()
        #expect(defaults.object(forKey: OutputMute.leftKey) != nil)

        // Another check, through another output, while it's still away.
        outputs.current = 9
        outputs.mutes[9] = false
        mute.mute()
        mute.restore()
        #expect(outputs.mutes[9] == false && defaults.object(forKey: OutputMute.leftKey) != nil)

        outputs.uids[7] = "BuiltInSpeaker" // back, still muted
        OutputMute(outputs: outputs, defaults: defaults).restoreIfLeft()
        #expect(outputs.mutes[7] == false && defaults.object(forKey: OutputMute.leftKey) == nil)
    }
}
