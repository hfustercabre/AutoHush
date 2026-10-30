import AppKit
import ScriptablePlayers

/// What an Apple event asks, read before a fake's lock: descriptors aren't
/// Sendable.
package struct SentEvent {
    /// Its class and ID, as text: "coregetd", "jukePaus".
    package let code: String
    /// Its direct object (`----`).
    package let direct: NSAppleEventDescriptor?
    /// The property it reads or sets (its direct object's `seld`).
    package let property: OSType?
    /// The value it sets (`data`), as a number.
    package let value: Int?

    package init(_ event: NSAppleEventDescriptor) {
        code = Self.text(event.eventClass) + Self.text(event.eventID)
        direct = event.paramDescriptor(forKeyword: fourCharCode("----"))
        property = direct?.forKeyword(fourCharCode("seld"))?.typeCodeValue
        value = event.paramDescriptor(forKeyword: fourCharCode("data")).map { Int($0.int32Value) }
    }

    /// A four-char code as its text ("jukePaus" is "juke" and "Paus").
    package static func text(_ code: OSType) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, encoding: .macOSRoman) ?? "?"
    }
}
