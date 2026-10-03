import Foundation

/// How a player turns its volume number (0–100) into loudness:
/// gain = (volume / 100) ^ exponent. Fades use it to move at a steady rate
/// in decibels, which is how loudness is heard.
///
/// Measure a player's curve with `swift run measure-volume-curve`.
package struct VolumeCurve: Equatable, Sendable {
    package let exponent: Double

    package init(exponent: Double) {
        self.exponent = exponent
    }

    /// Gain proportional to the volume number.
    package static let linear = VolumeCurve(exponent: 1)
    /// Gain proportional to the cube of the volume number: half volume is
    /// about −18 dB.
    package static let cubic = VolumeCurve(exponent: 3)

    /// Level relative to full volume; −∞ at 0.
    package func decibels(atVolume volume: Double) -> Double {
        volume > 0 ? 20 * exponent * log10(volume / 100) : -.infinity
    }

    /// The volume number that gives `decibels` relative to full volume.
    package func volume(atDecibels decibels: Double) -> Double {
        100 * pow(10, decibels / (20 * exponent))
    }
}
