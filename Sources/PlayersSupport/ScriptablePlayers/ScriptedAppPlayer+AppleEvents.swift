import AppKit
import Foundation

// ScriptedAppPlayer: its Apple events, from the codes its dictionary gave
// as text ("spfyPaus", "docu"), as AutoHush's ScriptablePlayer builds its own.
// Player Check sends its events with these too, so a check's AppleScript is
// AutoHush's.
extension ScriptedAppPlayer {
    typealias Code = ScriptablePlayer.Code

    /// A code read from a dictionary at run time as a number ("spfy" →
    /// 0x73706679): `fourCharCode` takes only literals.
    package static func code(_ text: String) -> OSType {
        text.utf8.prefix(4).reduce(0) { ($0 << 8) | OSType($1) }
    }

    /// The command `code` (suite, then command: "spfyPaus"), told which
    /// document to act on when `target` names one.
    package static func makeCommandEvent(_ code: String, to target: NSAppleEventDescriptor? = nil,
                                 processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        let event = ScriptablePlayer.makeCommandEvent(suite: Self.code(String(code.prefix(4))), Self.code(String(code.suffix(4))),
                                                      processIdentifier: pid)
        if let target { event.setParam(target, forKeyword: Code.directObject) }
        return event
    }

    /// `get` of what `specifier` names (a document's property).
    package static func makeGetDataEvent(_ specifier: NSAppleEventDescriptor, processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        ScriptablePlayer.makeGetDataEvent(specifier, processIdentifier: pid)
    }

    /// `set` of what `specifier` names (a document's property) to `value`.
    static func makeSetDataEvent(_ specifier: NSAppleEventDescriptor, to value: NSAppleEventDescriptor,
                                 processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        ScriptablePlayer.makeSetDataEvent(specifier, to: value, processIdentifier: pid)
    }

    /// The object specifier for the app's documents of class `documentClass`:
    /// the one named `name`, else the one at `index` (1: the front one, as
    /// AppleScript's "document 1"), else every one (both nil).
    package static func documentSpecifier(_ documentClass: String, named name: String? = nil, index: Int? = nil) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        let specifier = record.coerce(toDescriptorType: Code.objectSpecifier) ?? record
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: code(documentClass)), forKeyword: Code.desiredClass)
        specifier.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: Code.container)
        if let name {
            specifier.setDescriptor(NSAppleEventDescriptor(enumCode: code("name")), forKeyword: Code.keyForm)
            specifier.setDescriptor(NSAppleEventDescriptor(string: name), forKeyword: Code.keyData)
        } else if let index {
            specifier.setDescriptor(NSAppleEventDescriptor(enumCode: code("indx")), forKeyword: Code.keyForm)
            specifier.setDescriptor(NSAppleEventDescriptor(int32: Int32(index)), forKeyword: Code.keyData)
        } else {
            specifier.setDescriptor(NSAppleEventDescriptor(enumCode: code("indx")), forKeyword: Code.keyForm)
            var all = code("all ")
            specifier.setDescriptor(NSAppleEventDescriptor(descriptorType: code("abso"), bytes: &all, length: 4)!, forKeyword: Code.keyData)
        }
        return specifier
    }

    /// The object specifier for the property `property` of `container`.
    package static func propertySpecifier(_ property: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        ScriptablePlayer.propertySpecifier(code(property), of: container)
    }
}
