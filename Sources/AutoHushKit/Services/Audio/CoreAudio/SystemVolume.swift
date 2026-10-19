import CoreAudio
import Foundation

/// The Mac's output volume, as the volume keys change it: each of an
/// output's volume controls in decibels (its main one, or one per channel,
/// so the balance is kept).
package protocol SystemVolumeControlling: OutputDevices {
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

    package func volume(of device: AudioObjectID) -> SystemVolume? {
        // The main control, else the first two channels' (some devices have only those).
        var decibels: [AudioObjectPropertyElement: Float] = [:]
        for element in CoreAudioProperty.settableOutputElements(kAudioDevicePropertyVolumeDecibels, of: device) {
            if let value = CoreAudioProperty.value(kAudioDevicePropertyVolumeDecibels, of: device, scope: kAudioDevicePropertyScopeOutput,
                                                   element: element, initial: Float32(0)) {
                decibels[element] = value
            }
        }
        guard let element = decibels.keys.first else { return nil }
        let range = CoreAudioProperty.value(kAudioDevicePropertyVolumeRangeDecibels, of: device, scope: kAudioDevicePropertyScopeOutput,
                                            element: element, initial: AudioValueRange())
        return SystemVolume(decibels: decibels, lowest: Float(range?.mMinimum ?? -96))
    }

    package func setDecibels(_ decibels: [AudioObjectPropertyElement: Float], of device: AudioObjectID) {
        for (element, value) in decibels {
            CoreAudioProperty.set(kAudioDevicePropertyVolumeDecibels, of: device, scope: kAudioDevicePropertyScopeOutput,
                                  element: element, to: Float32(value))
        }
    }
}
