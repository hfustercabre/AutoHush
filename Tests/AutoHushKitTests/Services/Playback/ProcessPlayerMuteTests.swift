import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("ProcessPlayerMute", .waitsTimeLimit)
struct ProcessPlayerMuteTests {
    private func playerMute(running pid: Locked<pid_t?>, muter: FakeMuter, taps: Bool = true,
                            recording: Bool = true) -> ProcessPlayerMute {
        ProcessPlayerMute(bundleID: "org.videolan.vlc", muter: muter, tapsAllowed: { taps },
                          running: { _ in pid.value }, audioRecordingAllowed: { recording })
    }

    @Test("it mutes the running player and lets it through again; a second unmute does nothing")
    func mutesAndUnmutes() async {
        let muter = FakeMuter(), pid = Locked<pid_t?>(42)
        let mute = playerMute(running: pid, muter: muter)
        #expect(await mute.mute())
        #expect(muter.muted == [42])
        await mute.unmute()
        await mute.unmute()
        #expect(muter.log == ["mute 42", "unmute 42"])
    }

    @Test("not running, in AntiDot mode, without Audio Recording, or refused by the tap, it can't mute, and nothing is left to unmute")
    func cantMute() async {
        for (running, taps, recording, canMute) in [(nil, true, true, true), (pid_t(42), false, true, true),
                                                    (pid_t(42), true, false, true), (pid_t(42), true, true, false)] {
            let muter = FakeMuter()
            muter.canMute = canMute
            let mute = playerMute(running: Locked(running), muter: muter, taps: taps, recording: recording)
            #expect(await mute.mute() == false)
            await mute.unmute()
            #expect(muter.log.isEmpty)
        }
    }

    @Test("relaunched while muted, the old process is let through and the new one muted; one that can't be muted says so")
    func followsRelaunch() async {
        let muter = FakeMuter(), pid = Locked<pid_t?>(42)
        let mute = playerMute(running: pid, muter: muter)
        #expect(await mute.mute())
        #expect(await mute.followRelaunch()) // the same process: nothing to do
        pid.value = 43
        #expect(await mute.followRelaunch())
        #expect(muter.log == ["mute 42", "unmute 42", "mute 43"])
        pid.value = 44
        muter.canMute = false
        #expect(await mute.followRelaunch() == false)
        await mute.unmute()
        #expect(muter.log == ["mute 42", "unmute 42", "mute 43", "unmute 43"])
    }

    @Test("not muted, a relaunch needs nothing")
    func relaunchUnmuted() async {
        let muter = FakeMuter()
        #expect(await playerMute(running: Locked(42), muter: muter).followRelaunch())
        #expect(muter.log.isEmpty)
    }
}
