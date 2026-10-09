import AppKit
import Foundation
import AutoHushKit

// Pure Apple event construction, reply decoding and error mapping for
// ScriptablePlayer. Nothing here sends events, so it is fully unit-tested.

extension ScriptablePlayer {
    /// Four-char codes the scriptable music apps share (Spotify's
    /// `Spotify.sdef`, Music's `com.apple.Music.sdef`), and those of the
    /// standard Apple event suites. Only the suite of pause and play differs
    /// from app to app; it's in the profile.
    package enum Code {
        package static let coreSuite = fourCharCode("core")
        package static let getData = fourCharCode("getd")
        package static let setData = fourCharCode("setd")
        package static let setDataValue = fourCharCode("data")
        package static let pause = fourCharCode("Paus")
        package static let play = fourCharCode("Play")
        package static let playerStateProperty = fourCharCode("pPlS")
        package static let soundVolumeProperty = fourCharCode("pVol")
        package static let stateStopped = fourCharCode("kPSS")
        package static let statePlaying = fourCharCode("kPSP")
        package static let statePaused = fourCharCode("kPSp")
        /// Music only: seeking still counts as playing.
        package static let stateFastForwarding = fourCharCode("kPSF")
        package static let stateRewinding = fourCharCode("kPSR")

        package static let directObject = fourCharCode("----")
        package static let errorNumber = fourCharCode("errn")
        package static let errorString = fourCharCode("errs")
        package static let desiredClass = fourCharCode("want")
        package static let keyForm = fourCharCode("form")
        package static let keyData = fourCharCode("seld")
        package static let container = fourCharCode("from")
        package static let property = fourCharCode("prop")
        package static let objectSpecifier = fourCharCode("obj ")
    }

    // MARK: - Event construction (pure, unit-tested)

    /// `get player state` — a `core/getd` event whose direct object is an
    /// object specifier for the application's `pPlS` property.
    package static func makeGetPlayerStateEvent(processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        makeGetPropertyEvent(Code.playerStateProperty, processIdentifier: pid)
    }

    /// `get sound volume` (`pVol`, 0–100).
    package static func makeGetVolumeEvent(processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        makeGetPropertyEvent(Code.soundVolumeProperty, processIdentifier: pid)
    }

    /// `set sound volume to <volume>`.
    package static func makeSetVolumeEvent(_ volume: Int, processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        makeSetPropertyEvent(Code.soundVolumeProperty, to: volume, processIdentifier: pid)
    }

    /// `get <property>` of the application — a `core/getd` event.
    package static func makeGetPropertyEvent(_ property: DescType, processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        let event = coreEvent(Code.getData, processIdentifier: pid)
        event.setParam(propertySpecifier(property), forKeyword: Code.directObject)
        return event
    }

    /// `set <property> to <value>` of the application — a `core/setd` event.
    package static func makeSetPropertyEvent(
        _ property: DescType, to value: Int, processIdentifier pid: pid_t
    ) -> NSAppleEventDescriptor {
        let event = coreEvent(Code.setData, processIdentifier: pid)
        event.setParam(propertySpecifier(property), forKeyword: Code.directObject)
        event.setParam(NSAppleEventDescriptor(int32: Int32(value)), forKeyword: Code.setDataValue)
        return event
    }

    private static func coreEvent(_ eventID: AEEventID, processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        appleEvent(Code.coreSuite, eventID, processIdentifier: pid)
    }

    /// A parameterless command of the app's own suite, such as `pause` or `play`.
    package static func makeCommandEvent(
        suite: AEEventClass, _ eventID: AEEventID, processIdentifier pid: pid_t
    ) -> NSAppleEventDescriptor {
        appleEvent(suite, eventID, processIdentifier: pid)
    }

    private static func appleEvent(
        _ eventClass: AEEventClass, _ eventID: AEEventID, processIdentifier pid: pid_t
    ) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor.appleEvent(
            withEventClass: eventClass,
            eventID: eventID,
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }

    /// Object specifier for `property <code> of application`.
    package static func propertySpecifier(_ property: DescType) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: Code.property), forKeyword: Code.desiredClass)
        record.setDescriptor(NSAppleEventDescriptor(enumCode: Code.property), forKeyword: Code.keyForm)
        record.setDescriptor(NSAppleEventDescriptor(typeCode: property), forKeyword: Code.keyData)
        record.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: Code.container)
        return record.coerce(toDescriptorType: Code.objectSpecifier) ?? record
    }

    // MARK: - Reply decoding and error mapping (pure, unit-tested)

    package static func playerState(fromReply reply: PlayerReply) -> PlayerState {
        guard let code = reply.directObjectCode else { return .unknown }
        return playerState(fromEnumCode: code)
    }

    /// The volume in the reply, 0–100, as `reading` corrects it (see
    /// `ScriptablePlayerProfile.readVolume`).
    package static func volume(fromReply reply: PlayerReply, reading: (Int) -> Int) -> Int? {
        guard let reported = reply.directObjectInteger else { return nil }
        return min(max(reading(reported), 0), 100)
    }

    package static func playerState(fromEnumCode code: OSType) -> PlayerState {
        switch code {
        case Code.statePlaying, Code.stateFastForwarding, Code.stateRewinding: return .playing
        case Code.statePaused: return .paused
        case Code.stateStopped: return .stopped
        default: return .unknown
        }
    }

    /// An error the app reported inside an otherwise delivered reply.
    package static func replyError(_ reply: NSAppleEventDescriptor) -> MusicPlayerError? {
        guard let number = reply.paramDescriptor(forKeyword: Code.errorNumber) else { return nil }
        let code = Int(number.int32Value)
        guard code != 0 else { return nil }
        let message = reply.paramDescriptor(forKeyword: Code.errorString)?.stringValue
        return mapError(number: code, message: message)
    }

    /// Maps an error thrown by `sendEvent` (an `NSOSStatusErrorDomain` error).
    package static func mapError(_ error: any Error) -> MusicPlayerError {
        if let error = error as? MusicPlayerError { return error }
        let nsError = error as NSError
        return mapError(number: nsError.code, message: nil)
    }

    /// Maps an Apple event error number to a typed `MusicPlayerError`.
    package static func mapError(number: Int, message: String?) -> MusicPlayerError {
        switch number {
        case -1743: // errAEEventNotPermitted
            return .automationPermissionDenied
        case -600:  // procNotFound: the app quit between the check and the send
            return .playerNotRunning
        case -1712: // errAETimeout: the app is busy or still starting up
            return .playerNotResponding
        default:
            return .playerCommandFailed(.appleEventError(number, message: message.flatMap { $0.isEmpty ? nil : $0 }))
        }
    }
}

/// The parts of an Apple event reply the players read, extracted on the
/// event queue so they can cross into the actors.
package struct PlayerReply: Sendable, Equatable {
    /// Enum or type code of the reply's direct object (`----`), if any.
    package let directObjectCode: OSType?
    /// The direct object as a number, if it is one (e.g. the volume).
    package let directObjectInteger: Int?
    /// The direct object as a truth value, if it is one (e.g. VLC's `playing`).
    package let directObjectBoolean: Bool?

    package init(directObjectCode: OSType? = nil, directObjectInteger: Int? = nil, directObjectBoolean: Bool? = nil) {
        self.directObjectCode = directObjectCode
        self.directObjectInteger = directObjectInteger
        self.directObjectBoolean = directObjectBoolean
    }

    package init(_ reply: NSAppleEventDescriptor) {
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
    }
}

/// Converts a four-character string such as `"core"` to its `OSType` value.
package func fourCharCode(_ string: StaticString) -> OSType {
    precondition(string.utf8CodeUnitCount == 4, "four-char codes have exactly four bytes")
    return string.withUTF8Buffer { bytes in
        bytes.reduce(0) { ($0 << 8) | OSType($1) }
    }
}
