import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit

/// Outputs and their mutes, in memory.
private final class Outputs: OutputMuting, @unchecked Sendable {
    let lock = NSLock()
    var current: AudioObjectID? = 7
    /// Each output's UID, and its mute (`nil`: it has no mute control).
    var uids: [AudioObjectID: String] = [7: "BuiltInSpeaker", 9: "USBDAC"]
    var mutes: [AudioObjectID: Bool] = [7: false]

    func defaultOutput() -> AudioObjectID? { lock.withLock { current } }
    func isMuted(_ device: AudioObjectID) -> Bool? { lock.withLock { mutes[device] } }
    func setMuted(_ muted: Bool, _ device: AudioObjectID) { lock.withLock { if mutes[device] != nil { mutes[device] = muted } } }
    func uid(of device: AudioObjectID) -> String? { lock.withLock { uids[device] } }
    func device(withUID uid: String) -> AudioObjectID? { lock.withLock { uids.first { $0.value == uid }?.key } }
}

@Suite("OutputMute")
struct OutputMuteTests {
    private func defaults() -> UserDefaults {
        let name = "OutputMuteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("it mutes the output sound plays through and puts it back, once")
    func mutesAndRestores() {
        let outputs = Outputs(), defaults = defaults()
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
        let outputs = Outputs(), defaults = defaults()
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
        let outputs = Outputs(), defaults = defaults()
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
}
