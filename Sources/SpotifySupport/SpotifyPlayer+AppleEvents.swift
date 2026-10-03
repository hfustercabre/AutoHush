import AppKit
import Foundation
import AutoHushKit

// Pure Apple event construction, reply decoding and error mapping for
// SpotifyPlayer. Nothing here sends events, so it is fully unit-tested.

extension SpotifyPlayer {
    /// Four-char codes from `Spotify.app/Contents/Resources/Spotify.sdef`
    /// and the standard Apple event suites.
    package enum Code {
        package static let coreSuite = fourCharCode("core")
        package static let getData = fourCharCode("getd")
        package static let setData = fourCharCode("setd")
        package static let setDataValue = fourCharCode("data")
        package static let spotifySuite = fourCharCode("spfy")
        package static let pause = fourCharCode("Paus")
        package static let play = fourCharCode("Play")
        package static let playerStateProperty = fourCharCode("pPlS")
        package static let soundVolumeProperty = fourCharCode("pVol")
        package static let stateStopped = fourCharCode("kPSS")
        package static let statePlaying = fourCharCode("kPSP")
        package static let statePaused = fourCharCode("kPSp")

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

    /// `set sound volume to <volume>` — a `core/setd` event.
    package static func makeSetVolumeEvent(_ volume: Int, processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        let event = coreEvent(Code.setData, processIdentifier: pid)
        event.setParam(propertySpecifier(Code.soundVolumeProperty), forKeyword: Code.directObject)
        event.setParam(NSAppleEventDescriptor(int32: Int32(volume)), forKeyword: Code.setDataValue)
        return event
    }

    private static func makeGetPropertyEvent(_ property: DescType, processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        let event = coreEvent(Code.getData, processIdentifier: pid)
        event.setParam(propertySpecifier(property), forKeyword: Code.directObject)
        return event
    }

    private static func coreEvent(_ eventID: AEEventID, processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        appleEvent(Code.coreSuite, eventID, processIdentifier: pid)
    }

    /// A parameterless Spotify suite command such as `pause` or `play`.
    package static func makeCommandEvent(_ eventID: AEEventID, processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        appleEvent(Code.spotifySuite, eventID, processIdentifier: pid)
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

    package static func playerState(fromReply reply: SpotifyReply) -> PlayerState {
        guard let code = reply.directObjectCode else { return .unknown }
        return playerState(fromEnumCode: code)
    }

    /// Spotify reports one less than the volume it was set to (set 50, read
    /// 49; measured for 1–99), so readings are corrected. Otherwise every
    /// fade that restores the volume it read would lower it by one.
    package static func volume(fromReply reply: SpotifyReply) -> Int? {
        guard let reported = reply.directObjectInteger else { return nil }
        return (1...99).contains(reported) ? reported + 1 : min(max(reported, 0), 100)
    }

    package static func playerState(fromEnumCode code: OSType) -> PlayerState {
        switch code {
        case Code.statePlaying: return .playing
        case Code.statePaused: return .paused
        case Code.stateStopped: return .stopped
        default: return .unknown
        }
    }

    /// An error Spotify reported inside an otherwise delivered reply.
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
        case -600:  // procNotFound: Spotify quit between the check and the send
            return .playerNotRunning
        case -1712: // errAETimeout: Spotify is busy or still starting up
            return .playerNotResponding
        default:
            let detail = message.flatMap { $0.isEmpty ? nil : $0 }
            return .playerCommandFailed(detail.map { "\($0) (OSStatus \(number))" } ?? "OSStatus \(number)")
        }
    }
}

/// The parts of an Apple event reply SpotifyPlayer reads, extracted on
/// the event queue so they can cross into the actor.
package struct SpotifyReply: Sendable, Equatable {
    /// Enum or type code of the reply's direct object (`----`), if any.
    package let directObjectCode: OSType?
    /// The direct object as a number, if it is one (e.g. the volume).
    package let directObjectInteger: Int?

    package init(directObjectCode: OSType? = nil, directObjectInteger: Int? = nil) {
        self.directObjectCode = directObjectCode
        self.directObjectInteger = directObjectInteger
    }

    package init(_ reply: NSAppleEventDescriptor) {
        guard let direct = reply.paramDescriptor(forKeyword: SpotifyPlayer.Code.directObject) else {
            directObjectCode = nil
            directObjectInteger = nil
            return
        }
        switch direct.descriptorType {
        case typeEnumerated: directObjectCode = direct.enumCodeValue
        case typeType: directObjectCode = direct.typeCodeValue
        default: directObjectCode = nil
        }
        directObjectInteger = direct.coerce(toDescriptorType: typeSInt32).map { Int($0.int32Value) }
    }
}

/// Converts a four-character string such as `"core"` to its `OSType` value.
package func fourCharCode(_ string: StaticString) -> OSType {
    precondition(string.utf8CodeUnitCount == 4, "four-char codes have exactly four bytes")
    return string.withUTF8Buffer { bytes in
        bytes.reduce(0) { ($0 << 8) | OSType($1) }
    }
}
