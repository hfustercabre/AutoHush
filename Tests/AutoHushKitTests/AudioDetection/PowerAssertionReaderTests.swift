import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("PowerAssertionReader")
struct PowerAssertionReaderTests {
    @Test("counts only system-sleep assertions a process holds itself")
    func filtering() {
        let assertions: [NSNumber: [[String: Any]]] = [
            // Chrome: its own "Playing audio" assertion.
            50680: [["AssertType": "NoIdleSleepAssertion", "AssertName": "Playing audio"]],
            // VLC: its own playback assertion.
            84715: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "VLC media playback"]],
            // coreaudiod: one per running stream, on behalf of the app — ignored.
            76737: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "com.apple.audio.BuiltInSpeakerDevice.context.preventuseridlesleep",
                     "AssertionOnBehalfOfPID": NSNumber(value: 57954)]],
            // runningboardd: background task on behalf of an app — ignored.
            639: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "Shared Background Assertion",
                   "AssertionOnBehalfOfPID": NSNumber(value: 70071)]],
            // A video player keeping only the display awake — ignored.
            1234: [["AssertType": "PreventUserIdleDisplaySleep", "AssertName": "Video"]],
        ]
        #expect(IOKitPowerAssertionReader.pidsKeepingSystemAwake(in: assertions) == [50680, 84715])
    }

    @Test("the real system can be read")
    func readsSystem() {
        _ = IOKitPowerAssertionReader().pidsKeepingSystemAwake() // must not crash or require permission
    }
}
