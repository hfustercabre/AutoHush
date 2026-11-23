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
    /// The top of its dB range: above 0 for an output with gain.
    package let highest: Float
    package var translatesToScalar: (@Sendable (Float) -> Float)? {
        get { lock.withLock { _translates } }
        set { lock.withLock { _translates = newValue } }
    }
    private var _translates: (@Sendable (Float) -> Float)?

    package init(_ decibels: [AudioObjectPropertyElement: Float]?, lowest: Float = -60, highest: Float = 0) {
        self.lowest = lowest
        self.highest = highest
        _scalars = decibels.map { $0.mapValues { 1 - $0 / lowest } }
    }

    /// The volume on the keys' scale, as set or read (a broken value too).
    package var scalars: [AudioObjectPropertyElement: Float]? {
        get { lock.withLock { _scalars } }
        set { lock.withLock { _scalars = newValue } }
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
        return lock.withLock { _scalars }.map { SystemVolume(scalars: $0, lowest: lowest, highest: highest) }
    }

    package func scalar(forDecibels decibels: Float, element: AudioObjectPropertyElement, of device: AudioObjectID) -> Float? {
        guard device == 42, translates else { return nil }
        return translatesToScalar?(decibels) ?? 1 - decibels / lowest
    }

    /// Whether it takes a volume set (`false`: refused, as a device can).
    package var takesSets = true
    /// No translation between its volume and dB (Background Music's
    /// device); its dB reading then, by its linear mapping, unless
    /// `decibelsSetTo` says what a dB set does to its volume.
    package var translates = true
    package var readsDecibels = true
    /// Whether it takes a volume set in dB (`false`: refused).
    package var takesDecibelSets = true
    package var decibelsSetTo: (@Sendable (Float) -> Float)? {
        get { lock.withLock { _decibelsSetTo } }
        set { lock.withLock { _decibelsSetTo = newValue } }
    }
    private var _decibelsSetTo: (@Sendable (Float) -> Float)?

    @discardableResult
    package func setScalars(_ scalars: [AudioObjectPropertyElement: Float], of device: AudioObjectID) -> Bool {
        lock.withLock {
            guard takesSets else { return false }
            // Only those given, as Core Audio sets them (S-3 of 1.4.5's review).
            _scalars = (_scalars ?? [:]).merging(scalars) { $1 }
            _sets.append(scalars)
            return true
        }
    }

    package func decibels(of element: AudioObjectPropertyElement, of device: AudioObjectID) -> Float? {
        guard device == 42, readsDecibels else { return nil }
        return lock.withLock { _scalars?[element] }.map { lowest * (1 - $0) }
    }

    @discardableResult
    package func setDecibels(_ decibels: [AudioObjectPropertyElement: Float], of device: AudioObjectID) -> Bool {
        guard takesDecibelSets else { return false }
        let scalars = lock.withLock { () -> [AudioObjectPropertyElement: Float] in
            let map = _decibelsSetTo
            return decibels.mapValues { map?($0) ?? 1 - $0 / lowest }
        }
        return setScalars(scalars, of: device)
    }
}
