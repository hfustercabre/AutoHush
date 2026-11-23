import CoreAudio
import Foundation
import AutoHushKit

// Stand-ins for the Mac's outputs: their mutes (Add an App's check) and
// their volume (Level the volume). Shared by the engine's tests and the
// app's (AppDelegate), so no test mutes or turns down the machine it runs on.

/// An output whose volume is per channel (or main), or none, in memory:
/// sound plays through 42 ("Speakers"). Kept on the volume keys' scale (0
/// to 1), translated to and from dB linearly over `lowest`…0 (as the
/// Sony WF-1000XM6 headphones' own translation read, 2026-11-23: 0.36 is
/// -25.6 dB, 0.5 -20, 0.25 -30, of -40); given and read in
/// dB, to 0.01 dB. `translatesToScalar` replaces the dB-to-scale
/// translation, for an output that translates wrongly.
package final class MockSystemVolume: SystemVolumeControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var _scalars: [AudioObjectPropertyElement: Float]?
    private var _sets: [[AudioObjectPropertyElement: Float]] = []
    package let lowest: Float
    package var translatesToScalar: (@Sendable (Float) -> Float)?

    package init(_ decibels: [AudioObjectPropertyElement: Float]?, lowest: Float = -60) {
        self.lowest = lowest
        _scalars = decibels.map { $0.mapValues { 1 - $0 / lowest } }
    }

    /// The volume in dB, to 0.01 dB.
    package var decibels: [AudioObjectPropertyElement: Float]? {
        get { lock.withLock { _scalars.map { $0.mapValues(dB) } } }
        set { lock.withLock { _scalars = newValue.map { $0.mapValues { 1 - $0 / lowest } } } }
    }

    /// Each volume set, in turn, in dB.
    package var sets: [[AudioObjectPropertyElement: Float]] { lock.withLock { _sets.map { $0.mapValues(dB) } } }

    private func dB(_ scalar: Float) -> Float { (lowest * (1 - scalar) * 100).rounded() / 100 }

    package func defaultOutput() -> AudioObjectID? { 42 }
    package func uid(of device: AudioObjectID) -> String? { device == 42 ? "Speakers" : nil }
    package func device(withUID uid: String) -> AudioObjectID? { uid == "Speakers" ? 42 : nil }

    package func volume(of device: AudioObjectID) -> SystemVolume? {
        guard device == 42 else { return nil }
        return lock.withLock { _scalars }.map { SystemVolume(scalars: $0, lowest: lowest) }
    }

    package func decibels(forScalar scalar: Float, element: AudioObjectPropertyElement, of device: AudioObjectID) -> Float? {
        device == 42 ? lowest * (1 - scalar) : nil
    }

    package func scalar(forDecibels decibels: Float, element: AudioObjectPropertyElement, of device: AudioObjectID) -> Float? {
        guard device == 42 else { return nil }
        return translatesToScalar?(decibels) ?? 1 - decibels / lowest
    }

    package func setScalars(_ scalars: [AudioObjectPropertyElement: Float], of device: AudioObjectID) {
        lock.withLock {
            _scalars = scalars
            _sets.append(scalars)
        }
    }
}
