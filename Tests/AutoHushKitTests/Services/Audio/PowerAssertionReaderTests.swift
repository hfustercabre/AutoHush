import Foundation
import IOKit.pwr_mgt
import Testing
@testable import AutoHushKit

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

    @Test("the real system is read: an assertion this process holds is its own, keeping the Mac awake, by its name")
    func readsSystem() throws {
        let name = "AutoHush test: PowerAssertionReaderTests"
        var id = IOPMAssertionID(0)
        try #require(IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &id) == kIOReturnSuccess)
        defer { IOPMAssertionRelease(id) }
        // Needs no permission; should macOS change what it answers, every app would be judged by its open stream.
        #expect(IOKitPowerAssertionReader().assertionsByProcess()[getpid()]?.contains(PowerAssertion(.system, name)) == true)
    }
}
