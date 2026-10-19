import CoreAudio
import Foundation

/// The mute of the Mac's outputs, as the mute key sets it.
package protocol OutputMuting: OutputDevices {
    /// Whether the output is muted; `nil` for one with no mute it can set
    /// (some HDMI, DisplayPort and USB outputs).
    func isMuted(_ device: AudioObjectID) -> Bool?
    func setMuted(_ muted: Bool, _ device: AudioObjectID)
    /// Calls `onChange` (on a queue of its own) each time the output's mute
    /// changes, until the listener it returns is let go; `nil` when it can't
    /// be listened to.
    func observeMute(of device: AudioObjectID, _ onChange: @escaping @Sendable () -> Void) -> AnyObject?
    /// Calls `onChange` (on a queue of its own) each time sound moves to
    /// another output, until the listener it returns is let go; `nil` when
    /// it can't be listened to.
    func observeDefaultOutput(_ onChange: @escaping @Sendable () -> Void) -> AnyObject?
}

/// `OutputMuting` through Core Audio's device mute
/// (`kAudioDevicePropertyMute` on the output scope): its main control, else
/// its first two channels'.
package struct CoreAudioOutputMute: OutputMuting {
    package init() {}

    package func isMuted(_ device: AudioObjectID) -> Bool? {
        guard let element = Self.elements(device).first else { return nil }
        return CoreAudioProperty.value(kAudioDevicePropertyMute, of: device, scope: kAudioDevicePropertyScopeOutput,
                                       element: element, initial: UInt32(0)).map { $0 != 0 }
    }

    package func setMuted(_ muted: Bool, _ device: AudioObjectID) {
        for element in Self.elements(device) {
            CoreAudioProperty.set(kAudioDevicePropertyMute, of: device, scope: kAudioDevicePropertyScopeOutput,
                                  element: element, to: UInt32(muted ? 1 : 0))
        }
    }

    package func observeMute(of device: AudioObjectID, _ onChange: @escaping @Sendable () -> Void) -> AnyObject? {
        PropertyListener(object: device, addresses: Self.elements(device).map {
            CoreAudioProperty.outputAddress(kAudioDevicePropertyMute, $0)
        }, onChange: onChange)
    }

    package func observeDefaultOutput(_ onChange: @escaping @Sendable () -> Void) -> AnyObject? {
        PropertyListener(object: CoreAudioProperty.systemObject,
                         addresses: [CoreAudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)], onChange: onChange)
    }

    /// The mute controls it can set: the main one, else both of the first
    /// two channels' (one alone would leave the other heard).
    private static func elements(_ device: AudioObjectID) -> [AudioObjectPropertyElement] {
        let elements = CoreAudioProperty.settableOutputElements(kAudioDevicePropertyMute, of: device)
        return elements == [kAudioObjectPropertyElementMain] || elements.count == 2 ? elements : []
    }
}

/// Listens to properties of a Core Audio object (an output's mute
/// controls, the system's default output) until it's let go.
private final class PropertyListener {
    private let object: AudioObjectID
    private let queue = DispatchQueue(label: "AutoHush.OutputMute")
    private let listener: AudioObjectPropertyListenerBlock
    private var addresses: [AudioObjectPropertyAddress] = []

    init?(object: AudioObjectID, addresses wanted: [AudioObjectPropertyAddress], onChange: @escaping @Sendable () -> Void) {
        self.object = object
        listener = { _, _ in onChange() }
        for var address in wanted where AudioObjectAddPropertyListenerBlock(object, &address, queue, listener) == noErr {
            addresses.append(address)
        }
        if addresses.isEmpty { return nil }
    }

    deinit {
        for var address in addresses {
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, listener)
        }
    }
}
