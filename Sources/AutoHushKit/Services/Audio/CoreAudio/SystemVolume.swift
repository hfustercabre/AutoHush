import CoreAudio
import Foundation

/// The Mac's output volume, as the volume keys change it: each of an
/// output's volume controls in decibels (its main one, or one per channel,
/// so the balance is kept).
package protocol SystemVolumeControlling: Sendable {
    /// The output sound plays through now.
    func defaultOutput() -> AudioObjectID?
    /// The output's settable volumes in dB, by element, and the lowest it
    /// takes; `nil` for an output with no volume control (HDMI, DisplayPort,
    /// a fixed-volume DAC).
    func volume(of device: AudioObjectID) -> SystemVolume?
    func setDecibels(_ decibels: [AudioObjectPropertyElement: Float], of device: AudioObjectID)
}

package struct SystemVolume: Equatable, Sendable {
    package var decibels: [AudioObjectPropertyElement: Float]
    package var lowest: Float

    package init(decibels: [AudioObjectPropertyElement: Float], lowest: Float) {
        self.decibels = decibels
        self.lowest = lowest
    }
}

/// `SystemVolumeControlling` through Core Audio's device volume
/// (`kAudioDevicePropertyVolumeDecibels` on the output scope).
package struct CoreAudioSystemVolume: SystemVolumeControlling {
    package init() {}

    package func defaultOutput() -> AudioObjectID? {
        let device = CoreAudioProperty.value(kAudioHardwarePropertyDefaultOutputDevice, of: CoreAudioProperty.systemObject,
                                             initial: AudioObjectID(kAudioObjectUnknown))
        return device == AudioObjectID(kAudioObjectUnknown) ? nil : device
    }

    package func volume(of device: AudioObjectID) -> SystemVolume? {
        // The main control, else the first two channels' (some devices have only those).
        for elements in [[kAudioObjectPropertyElementMain], [1, 2]] as [[AudioObjectPropertyElement]] {
            var decibels: [AudioObjectPropertyElement: Float] = [:]
            for element in elements where Self.isSettable(device, element) {
                if let value: Float32 = Self.read(kAudioDevicePropertyVolumeDecibels, of: device, element) { decibels[element] = value }
            }
            guard !decibels.isEmpty, let element = decibels.keys.first else { continue }
            let range: AudioValueRange? = Self.read(kAudioDevicePropertyVolumeRangeDecibels, of: device, element)
            return SystemVolume(decibels: decibels, lowest: Float(range?.mMinimum ?? -96))
        }
        return nil
    }

    package func setDecibels(_ decibels: [AudioObjectPropertyElement: Float], of device: AudioObjectID) {
        for (element, value) in decibels {
            var address = Self.address(kAudioDevicePropertyVolumeDecibels, element)
            var data = Float32(value)
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &data)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    private static func isSettable(_ device: AudioObjectID, _ element: AudioObjectPropertyElement) -> Bool {
        var address = address(kAudioDevicePropertyVolumeDecibels, element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func read<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, of device: AudioObjectID,
                                                 _ element: AudioObjectPropertyElement) -> T? {
        var address = address(selector, element)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }
}
