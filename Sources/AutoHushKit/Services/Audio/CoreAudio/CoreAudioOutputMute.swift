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
    /// Calls `onChange` (on a queue of its own) each time the output's mute
    /// changes, until the listener it returns is let go; `nil` when it can't
    /// be listened to.
    func observeMute(of device: AudioObjectID, _ onChange: @escaping @Sendable () -> Void) -> AnyObject?
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
        var address = CoreAudioProperty.outputAddress(kAudioDevicePropertyMute, element)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    package func setMuted(_ muted: Bool, _ device: AudioObjectID) {
        for element in Self.elements(device) {
            var address = CoreAudioProperty.outputAddress(kAudioDevicePropertyMute, element)
            var value: UInt32 = muted ? 1 : 0
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }

    package func uid(of device: AudioObjectID) -> String? {
        CoreAudioProperty.string(kAudioDevicePropertyDeviceUID, of: device)
    }

    package func device(withUID uid: String) -> AudioObjectID? {
        CoreAudioProperty.device(withUID: uid)
    }

    package func observeMute(of device: AudioObjectID, _ onChange: @escaping @Sendable () -> Void) -> AnyObject? {
        MuteListener(device: device, elements: Self.elements(device), onChange: onChange)
    }

    /// The mute controls it can set: the main one, else both of the first
    /// two channels' (one alone would leave the other heard).
    private static func elements(_ device: AudioObjectID) -> [AudioObjectPropertyElement] {
        let elements = CoreAudioProperty.settableOutputElements(kAudioDevicePropertyMute, of: device)
        return elements == [kAudioObjectPropertyElementMain] || elements.count == 2 ? elements : []
    }
}

/// Listens to an output's mute controls until it's let go.
private final class MuteListener {
    private let device: AudioObjectID
    private let queue = DispatchQueue(label: "AutoHush.OutputMute")
    private let listener: AudioObjectPropertyListenerBlock
    private var addresses: [AudioObjectPropertyAddress] = []

    init?(device: AudioObjectID, elements: [AudioObjectPropertyElement], onChange: @escaping @Sendable () -> Void) {
        self.device = device
        listener = { _, _ in onChange() }
        for element in elements {
            var address = CoreAudioProperty.outputAddress(kAudioDevicePropertyMute, element)
            if AudioObjectAddPropertyListenerBlock(device, &address, queue, listener) == noErr { addresses.append(address) }
        }
        if addresses.isEmpty { return nil }
    }

    deinit {
        for var address in addresses {
            AudioObjectRemovePropertyListenerBlock(device, &address, queue, listener)
        }
    }
}
