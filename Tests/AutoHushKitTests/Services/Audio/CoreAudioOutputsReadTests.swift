import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

/// The Mac's own outputs, only read: never muted nor changed, the tests
/// run on it.
@Suite("Core Audio's outputs, read")
struct CoreAudioOutputsReadTests {
    /// Shown as skipped on a Mac with no output at all (a runner), not
    /// passed having read nothing (the full check, 2026-10-20).
    @Test("the output sound plays through is found again by its lasting ID, and its mute reads a value or none",
          .enabled(if: CoreAudioOutputMute().defaultOutput() != nil, "no sound output here"))
    func defaultOutputReads() throws {
        let outputs = CoreAudioOutputMute(), volume = CoreAudioSystemVolume()
        let device = try #require(outputs.defaultOutput())
        let uid = try #require(outputs.uid(of: device))
        #expect(outputs.device(withUID: uid) == device)
        #expect(volume.device(withUID: uid) == device && volume.defaultOutput() == device)
        _ = outputs.isMuted(device) // a value, or nil for an output with no mute: either reads without failing
        #expect(outputs.device(withUID: "AutoHush.NoSuchOutput.\(UUID().uuidString)") == nil)
    }

    @Test("an output control of no object reads nothing and takes nothing")
    func noObject() {
        let none = AudioObjectID(kAudioObjectUnknown), output = kAudioDevicePropertyScopeOutput
        #expect(CoreAudioProperty.value(kAudioDevicePropertyMute, of: none, scope: output, element: 1, initial: UInt32(0)) == nil)
        #expect(!CoreAudioProperty.set(kAudioDevicePropertyMute, of: none, scope: output, element: 1, to: UInt32(1)))
    }
}
