import CoreAudio
import Foundation

/// The Mac's output volume, as the volume keys change it: each of an
/// output's volume controls on the keys' scale (0 to 1; its main one, or
/// one per channel, so the balance is kept), with the output's own
/// translation to and from decibels. Read and set on that scale, not in
/// decibels: an output can report its decibels wrongly (Sony WF-1000XM6
/// headphones read 0 dB at any volume, 2026-11-23), and a volume set from
/// that went up instead of down.
package protocol SystemVolumeControlling: OutputDevices {
    /// The output's settable volumes on the keys' scale, by element, and
    /// the lowest it takes in dB; `nil` for an output with no volume
    /// control (HDMI, DisplayPort, a fixed-volume DAC).
    func volume(of device: AudioObjectID) -> SystemVolume?
    /// The output's own translation of a volume on the keys' scale to dB,
    /// and back; `nil` when it has none.
    func decibels(forScalar scalar: Float, element: AudioObjectPropertyElement, of device: AudioObjectID) -> Float?
    func scalar(forDecibels decibels: Float, element: AudioObjectPropertyElement, of device: AudioObjectID) -> Float?
    func setScalars(_ scalars: [AudioObjectPropertyElement: Float], of device: AudioObjectID)
}

package struct SystemVolume: Equatable, Sendable {
    package var scalars: [AudioObjectPropertyElement: Float]
    package var lowest: Float

    package init(scalars: [AudioObjectPropertyElement: Float], lowest: Float) {
        self.scalars = scalars
        self.lowest = lowest
    }
}

/// `SystemVolumeControlling` through Core Audio's device volume
/// (`kAudioDevicePropertyVolumeScalar` on the output scope, translated by
/// the device's own `VolumeScalarToDecibels` and `VolumeDecibelsToScalar`).
package struct CoreAudioSystemVolume: SystemVolumeControlling {
    package init() {}

    package func volume(of device: AudioObjectID) -> SystemVolume? {
        // The main control, else the first two channels' (some devices have only those).
        var scalars: [AudioObjectPropertyElement: Float] = [:]
        for element in CoreAudioProperty.settableOutputElements(kAudioDevicePropertyVolumeScalar, of: device) {
            if let value = CoreAudioProperty.value(kAudioDevicePropertyVolumeScalar, of: device, scope: kAudioDevicePropertyScopeOutput,
                                                   element: element, initial: Float32(0)) {
                scalars[element] = value
            }
        }
        guard let element = scalars.keys.first else { return nil }
        let range = CoreAudioProperty.value(kAudioDevicePropertyVolumeRangeDecibels, of: device, scope: kAudioDevicePropertyScopeOutput,
                                            element: element, initial: AudioValueRange())
        return SystemVolume(scalars: scalars, lowest: Float(range?.mMinimum ?? -96))
    }

    package func decibels(forScalar scalar: Float, element: AudioObjectPropertyElement, of device: AudioObjectID) -> Float? {
        // A translation: the value read in is the one translated.
        CoreAudioProperty.value(kAudioDevicePropertyVolumeScalarToDecibels, of: device, scope: kAudioDevicePropertyScopeOutput,
                                element: element, initial: Float32(scalar))
    }

    package func scalar(forDecibels decibels: Float, element: AudioObjectPropertyElement, of device: AudioObjectID) -> Float? {
        CoreAudioProperty.value(kAudioDevicePropertyVolumeDecibelsToScalar, of: device, scope: kAudioDevicePropertyScopeOutput,
                                element: element, initial: Float32(decibels))
    }

    package func setScalars(_ scalars: [AudioObjectPropertyElement: Float], of device: AudioObjectID) {
        for (element, value) in scalars {
            CoreAudioProperty.set(kAudioDevicePropertyVolumeScalar, of: device, scope: kAudioDevicePropertyScopeOutput,
                                  element: element, to: Float32(value))
        }
    }
}
