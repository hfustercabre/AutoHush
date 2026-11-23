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
    /// The output's own translation of a level in dB to its volume on the
    /// keys' scale (the one its volume follows); `nil` when it has none.
    /// Not the other way: a MacBook Pro's speakers translate volume to dB
    /// on a straight line that doesn't match it (60 % read -25.4 dB, which
    /// translates back to 30 %), 2026-11-23.
    func scalar(forDecibels decibels: Float, element: AudioObjectPropertyElement, of device: AudioObjectID) -> Float?
    /// Whether the output took any (one it took stays set, so a lowering
    /// partly taken counts as made: R1 of 1.4.5's fixes' review).
    @discardableResult
    func setScalars(_ scalars: [AudioObjectPropertyElement: Float], of device: AudioObjectID) -> Bool
}

package struct SystemVolume: Equatable, Sendable {
    package var scalars: [AudioObjectPropertyElement: Float]
    /// The output's range in dB.
    package var lowest: Float
    package var highest: Float

    package init(scalars: [AudioObjectPropertyElement: Float], lowest: Float, highest: Float = 0) {
        self.scalars = scalars
        self.lowest = lowest
        self.highest = highest
    }
}

extension SystemVolumeControlling {
    /// The level in dB the output puts its volume `scalar` at, found on its
    /// dB-to-volume translation (`scalar(forDecibels:)`) by halving its
    /// range; `nil` when it can't be translated, or no level lands within
    /// `tolerance` of `scalar` (a scale that doesn't hold isn't trusted).
    package func decibels(at scalar: Float, element: AudioObjectPropertyElement, of device: AudioObjectID,
                          in volume: SystemVolume, tolerance: Float = 0.02) -> Float? {
        var low = volume.lowest, high = max(volume.lowest, volume.highest)
        for _ in 0..<24 {
            let middle = (low + high) / 2
            guard let value = self.scalar(forDecibels: middle, element: element, of: device), value.isFinite else { return nil }
            if value < scalar { low = middle } else { high = middle }
        }
        let level = (low + high) / 2
        guard let back = self.scalar(forDecibels: level, element: element, of: device), abs(back - scalar) <= tolerance else { return nil }
        return level
    }
}

/// `SystemVolumeControlling` through Core Audio's device volume
/// (`kAudioDevicePropertyVolumeScalar` on the output scope, translated by
/// the device's own `VolumeDecibelsToScalar`).
package struct CoreAudioSystemVolume: SystemVolumeControlling {
    package init() {}

    package func volume(of device: AudioObjectID) -> SystemVolume? {
        // The main control, else the first two channels' (some devices have only those).
        var scalars: [AudioObjectPropertyElement: Float] = [:]
        for element in CoreAudioProperty.settableOutputElements(kAudioDevicePropertyVolumeScalar, of: device) {
            if let value = CoreAudioProperty.value(kAudioDevicePropertyVolumeScalar, of: device, scope: kAudioDevicePropertyScopeOutput,
                                                   element: element, initial: Float32(0)),
               value.isFinite, (0...1).contains(value) { // a broken driver's value is no volume (X-1 of 1.4.5's review)
                scalars[element] = value
            }
        }
        guard let element = scalars.keys.first else { return nil }
        let range = CoreAudioProperty.value(kAudioDevicePropertyVolumeRangeDecibels, of: device, scope: kAudioDevicePropertyScopeOutput,
                                            element: element, initial: AudioValueRange())
        let lowest = range.map { Float($0.mMinimum) }.flatMap { $0.isFinite ? $0 : nil } ?? -96
        let highest = range.map { Float($0.mMaximum) }.flatMap { $0.isFinite && $0 >= lowest ? $0 : nil } ?? 0
        return SystemVolume(scalars: scalars, lowest: lowest, highest: highest)
    }

    package func scalar(forDecibels decibels: Float, element: AudioObjectPropertyElement, of device: AudioObjectID) -> Float? {
        CoreAudioProperty.value(kAudioDevicePropertyVolumeDecibelsToScalar, of: device, scope: kAudioDevicePropertyScopeOutput,
                                element: element, initial: Float32(decibels)).flatMap { $0.isFinite ? $0 : nil }
    }

    @discardableResult
    package func setScalars(_ scalars: [AudioObjectPropertyElement: Float], of device: AudioObjectID) -> Bool {
        var tookAny = false
        for (element, value) in scalars {
            tookAny = CoreAudioProperty.set(kAudioDevicePropertyVolumeScalar, of: device, scope: kAudioDevicePropertyScopeOutput,
                                            element: element, to: Float32(value)) || tookAny
        }
        return tookAny
    }
}
