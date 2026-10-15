import AppKit
import Foundation

// ScriptedAppPlayer: its Apple events, from the codes its dictionary gave
// as text ("spfyPaus", "docu"), as AutoHush's ScriptablePlayer builds its own.
extension ScriptedAppPlayer {
    typealias Code = ScriptablePlayer.Code

    /// A code read from a dictionary at run time as a number ("spfy" →
    /// 0x73706679): `fourCharCode` takes only literals.
    static func code(_ text: String) -> OSType {
        text.utf8.prefix(4).reduce(0) { ($0 << 8) | OSType($1) }
    }

    /// The command `code` (suite, then command: "spfyPaus"), told which
    /// document to act on when `target` names one.
    static func makeCommandEvent(_ code: String, to target: NSAppleEventDescriptor? = nil,
                                 processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        let event = ScriptablePlayer.makeCommandEvent(suite: Self.code(String(code.prefix(4))), Self.code(String(code.suffix(4))),
                                                      processIdentifier: pid)
        if let target { event.setParam(target, forKeyword: Code.directObject) }
        return event
    }

    /// `get` of what `specifier` names (a document's property).
    static func makeGetDataEvent(_ specifier: NSAppleEventDescriptor, processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        let event = ScriptablePlayer.makeCommandEvent(suite: Code.coreSuite, Code.getData, processIdentifier: pid)
        event.setParam(specifier, forKeyword: Code.directObject)
        return event
    }

    /// The object specifier for the app's documents of class `documentClass`:
    /// the one named `name`, the front one (`name` nil, `front`), or every one.
    static func documentSpecifier(_ documentClass: String, named name: String?? = .none) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        let specifier = record.coerce(toDescriptorType: Code.objectSpecifier) ?? record
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: code(documentClass)), forKeyword: Code.desiredClass)
        specifier.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: Code.container)
        switch name {
        case .some(.some(let name)):
            specifier.setDescriptor(NSAppleEventDescriptor(enumCode: code("name")), forKeyword: Code.keyForm)
            specifier.setDescriptor(NSAppleEventDescriptor(string: name), forKeyword: Code.keyData)
        case .some(.none):
            specifier.setDescriptor(NSAppleEventDescriptor(enumCode: code("indx")), forKeyword: Code.keyForm)
            specifier.setDescriptor(NSAppleEventDescriptor(int32: 1), forKeyword: Code.keyData)
        case .none:
            specifier.setDescriptor(NSAppleEventDescriptor(enumCode: code("indx")), forKeyword: Code.keyForm)
            var all = code("all ")
            specifier.setDescriptor(NSAppleEventDescriptor(descriptorType: code("abso"), bytes: &all, length: 4)!, forKeyword: Code.keyData)
        }
        return specifier
    }

    /// The object specifier for the property `property` of `container`.
    static func propertySpecifier(_ property: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: Code.property), forKeyword: Code.desiredClass)
        record.setDescriptor(NSAppleEventDescriptor(enumCode: Code.property), forKeyword: Code.keyForm)
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(property)), forKeyword: Code.keyData)
        record.setDescriptor(container, forKeyword: Code.container)
        return record.coerce(toDescriptorType: Code.objectSpecifier) ?? record
    }
}
