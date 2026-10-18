import CoreAudio
import Foundation

/// The mute of the Mac's outputs, as the mute key sets it.
package protocol OutputMuting: Sendable {
    /// The output sound plays through now.
    func defaultOutput() -> AudioObjectID?
    /// Whether the output is muted; `nil` for one with no mute it can set
    /// (some HDMI, DisplayPort and USB outputs).
    func isMuted(_ device: AudioObjectID) -> Bool?
    func setMuted(_ muted: Bool, _ device: AudioObjectID)
    /// The output's lasting ID, and the output with it now: its object ID
    /// changes from one launch to the next.
    func uid(of device: AudioObjectID) -> String?
    func device(withUID uid: String) -> AudioObjectID?
}

/// `OutputMuting` through Core Audio's device mute
/// (`kAudioDevicePropertyMute` on the output scope): its main control, else
/// its first two channels'.
package struct CoreAudioOutputMute: OutputMuting {
    package init() {}

    package func defaultOutput() -> AudioObjectID? {
        CoreAudioSystemVolume().defaultOutput()
    }

    package func isMuted(_ device: AudioObjectID) -> Bool? {
        guard let element = Self.elements(device).first else { return nil }
        var address = Self.address(element)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    package func setMuted(_ muted: Bool, _ device: AudioObjectID) {
        for element in Self.elements(device) {
            var address = Self.address(element)
            var value: UInt32 = muted ? 1 : 0
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }

    package func uid(of device: AudioObjectID) -> String? {
        CoreAudioProperty.string(kAudioDevicePropertyDeviceUID, of: device)
    }

    package func device(withUID uid: String) -> AudioObjectID? {
        var address = CoreAudioProperty.address(kAudioHardwarePropertyTranslateUIDToDevice)
        var qualifier: CFString = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &qualifier) { pointer in
            AudioObjectGetPropertyData(CoreAudioProperty.systemObject, &address, UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
        }
        return status == noErr && device != AudioObjectID(kAudioObjectUnknown) ? device : nil
    }

    /// The mute controls it can set: the main one, else both of the first
    /// two channels'.
    private static func elements(_ device: AudioObjectID) -> [AudioObjectPropertyElement] {
        if isSettable(device, kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        let channels: [AudioObjectPropertyElement] = [1, 2]
        return channels.allSatisfy { isSettable(device, $0) } ? channels : []
    }

    private static func address(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    private static func isSettable(_ device: AudioObjectID, _ element: AudioObjectPropertyElement) -> Bool {
        var address = address(element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }
}
