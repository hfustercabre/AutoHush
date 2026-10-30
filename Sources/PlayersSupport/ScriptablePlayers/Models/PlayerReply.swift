import AppKit
import Foundation

/// The parts of an Apple event reply the players read, extracted on the
/// event queue so they can cross into the actors.
package struct PlayerReply: Sendable, Equatable {
    /// Enum or type code of the reply's direct object (`----`), if any.
    let directObjectCode: OSType?
    /// The direct object as a number, if it is one (e.g. the volume).
    package let directObjectInteger: Int?
    /// The direct object as a truth value, if it is one (e.g. VLC's `playing`).
    package let directObjectBoolean: Bool?
    /// A list's items as texts and as truth values (each document's name, or
    /// whether it's playing: QuickTime Player's); empty for any other reply.
    var listTexts: [String] = []
    var listBooleans: [Bool] = []
    /// The direct object as a text, if it is one (a document's name).
    var directObjectText: String?
    /// The direct object as a real number, if it is one (a document's
    /// `audio volume`, 0–1: QuickTime Player's).
    var directObjectReal: Double?

    /// A reply made of these parts: for tests, whose stand-in apps answer
    /// with one.
    init(directObjectCode: OSType? = nil, directObjectInteger: Int? = nil, directObjectBoolean: Bool? = nil,
         listTexts: [String] = [], listBooleans: [Bool] = []) {
        self.directObjectCode = directObjectCode
        self.directObjectInteger = directObjectInteger
        self.directObjectBoolean = directObjectBoolean
        self.listTexts = listTexts
        self.listBooleans = listBooleans
    }

    init(_ reply: NSAppleEventDescriptor) {
        guard let direct = reply.paramDescriptor(forKeyword: ScriptablePlayer.Code.directObject) else {
            directObjectCode = nil
            directObjectInteger = nil
            directObjectBoolean = nil
            return
        }
        switch direct.descriptorType {
        case typeEnumerated: directObjectCode = direct.enumCodeValue
        case typeType: directObjectCode = direct.typeCodeValue
        default: directObjectCode = nil
        }
        switch direct.descriptorType {
        case typeTrue, typeFalse, typeBoolean: directObjectBoolean = direct.booleanValue
        default: directObjectBoolean = nil
        }
        directObjectInteger = directObjectBoolean == nil ? direct.coerce(toDescriptorType: typeSInt32).map { Int($0.int32Value) } : nil
        directObjectReal = directObjectBoolean == nil ? direct.coerce(toDescriptorType: typeIEEE64BitFloatingPoint)?.doubleValue : nil
        if [typeUnicodeText, typeUTF8Text, typeChar].contains(direct.descriptorType) { directObjectText = direct.stringValue }
        if direct.descriptorType == typeAEList, direct.numberOfItems > 0 {
            let items = (1...direct.numberOfItems).compactMap { direct.atIndex($0) }
            listTexts = items.map { $0.stringValue ?? "" }
            listBooleans = items.map(\.booleanValue)
        }
    }
}
