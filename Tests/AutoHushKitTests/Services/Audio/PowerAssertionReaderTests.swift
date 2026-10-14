import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("PowerAssertionReader")
struct PowerAssertionReaderTests {
    @Test("keeps each process's own system and display assertions, by name")
    func filtering() {
        let assertions: [NSNumber: [[String: Any]]] = [
            // Chrome: "Playing audio" keeps the Mac awake, "Video Wake Lock" the display.
            50680: [["AssertType": "NoIdleSleepAssertion", "AssertName": "Playing audio"],
                    ["AssertType": "NoDisplaySleepAssertion", "AssertName": "Video Wake Lock"]],
            // VLC: its own playback assertion.
            84715: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "VLC media playback"]],
            // WebKit: a visible video keeps only the display awake.
            90026: [["AssertType": "PreventUserIdleDisplaySleep", "AssertName": "com.apple.WebCore: HTMLMediaElement playback"]],
            // coreaudiod: one per running stream, on behalf of the app — ignored.
            76737: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "com.apple.audio.BuiltInSpeakerDevice.context.preventuseridlesleep",
                     "AssertionOnBehalfOfPID": NSNumber(value: 57954)]],
            // runningboardd: background task on behalf of an app — ignored.
            639: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "Shared Background Assertion",
                   "AssertionOnBehalfOfPID": NSNumber(value: 70071)]],
            // Other kinds of assertion — ignored.
            585: [["AssertType": "ApplePushServiceTask", "AssertName": "com.apple.apsd-lastpowerassertionlinger"]],
        ]
        #expect(IOKitPowerAssertionReader.assertionsByProcess(in: assertions) == [
            50680: [PowerAssertion(.system, "Playing audio"), PowerAssertion(.display, "Video Wake Lock")],
            84715: [PowerAssertion(.system, "VLC media playback")],
            90026: [PowerAssertion(.display, "com.apple.WebCore: HTMLMediaElement playback")],
        ])
    }

    @Test("the real system can be read")
    func readsSystem() {
        _ = IOKitPowerAssertionReader().assertionsByProcess() // must not crash or require permission
    }
}
