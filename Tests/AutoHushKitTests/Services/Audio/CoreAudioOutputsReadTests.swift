import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit

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

    /// Every output with a volume control, not only the default one: the
    /// VMs play through a loopback with none, but list their own sound
    /// device beside it (2026-11-24).
    private static var outputsWithVolume: [AudioObjectID] {
        let volume = CoreAudioSystemVolume()
        return CoreAudioProperty.objectIDs(kAudioHardwarePropertyDevices, of: CoreAudioProperty.systemObject)
            .filter { volume.volume(of: $0) != nil }
    }

    @Test("each output's volume, read on the volume keys' scale, is found again on its own dB-to-volume translation (read only)",
          .enabled(if: !outputsWithVolume.isEmpty, "no output with a volume control here"))
    func volumeTranslatesBack() throws {
        let volume = CoreAudioSystemVolume()
        for device in Self.outputsWithVolume {
            let current = try #require(volume.volume(of: device))
            for (element, scalar) in current.scalars {
                #expect((0...1).contains(scalar))
                let decibels = try #require(volume.decibels(at: scalar, element: element, of: device, in: current))
                #expect(decibels >= current.lowest - 0.01 && decibels <= current.highest + 0.01)
            }
        }
    }

    @Test("an output control of no object reads nothing and takes nothing")
    func noObject() {
        let none = AudioObjectID(kAudioObjectUnknown), output = kAudioDevicePropertyScopeOutput
        #expect(CoreAudioProperty.value(kAudioDevicePropertyMute, of: none, scope: output, element: 1, initial: UInt32(0)) == nil)
        #expect(!CoreAudioProperty.set(kAudioDevicePropertyMute, of: none, scope: output, element: 1, to: UInt32(1)))
    }
}
