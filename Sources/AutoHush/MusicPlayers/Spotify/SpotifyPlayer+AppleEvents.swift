import AppKit
import Foundation

// Pure Apple event construction, reply decoding and error mapping for
// SpotifyPlayer. Nothing here sends events, so it is fully unit-tested.

extension SpotifyPlayer {
    /// Four-char codes from `Spotify.app/Contents/Resources/Spotify.sdef`
    /// and the standard Apple event suites.
    enum Code {
        static let coreSuite = fourCharCode("core")
        static let getData = fourCharCode("getd")
        static let setData = fourCharCode("setd")
        static let setDataValue = fourCharCode("data")
        static let spotifySuite = fourCharCode("spfy")
        static let pause = fourCharCode("Paus")
        static let play = fourCharCode("Play")
        static let playerStateProperty = fourCharCode("pPlS")
        static let soundVolumeProperty = fourCharCode("pVol")
        static let stateStopped = fourCharCode("kPSS")
        static let statePlaying = fourCharCode("kPSP")
        static let statePaused = fourCharCode("kPSp")

        static let directObject = fourCharCode("----")
        static let errorNumber = fourCharCode("errn")
        static let errorString = fourCharCode("errs")
        static let desiredClass = fourCharCode("want")
        static let keyForm = fourCharCode("form")
        static let keyData = fourCharCode("seld")
        static let container = fourCharCode("from")
        static let property = fourCharCode("prop")
        static let objectSpecifier = fourCharCode("obj ")
    }

    // MARK: - Event construction (pure, unit-tested)

    /// `get player state` — a `core/getd` event whose direct object is an
    /// object specifier for the application's `pPlS` property.
    static func makeGetPlayerStateEvent(processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        makeGetPropertyEvent(Code.playerStateProperty, processIdentifier: pid)
    }

    /// `get sound volume` (`pVol`, 0–100).
    static func makeGetVolumeEvent(processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        makeGetPropertyEvent(Code.soundVolumeProperty, processIdentifier: pid)
    }

    /// `set sound volume to <volume>` — a `core/setd` event.
    static func makeSetVolumeEvent(_ volume: Int, processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
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
        NSAppleEventDescriptor.appleEvent(
            withEventClass: Code.coreSuite,
            eventID: eventID,
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }

    /// A parameterless Spotify suite command such as `pause` or `play`.
    static func makeCommandEvent(_ eventID: AEEventID, processIdentifier pid: pid_t) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor.appleEvent(
            withEventClass: Code.spotifySuite,
            eventID: eventID,
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }

    /// Object specifier for `property <code> of application`.
    static func propertySpecifier(_ property: DescType) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: Code.property), forKeyword: Code.desiredClass)
        record.setDescriptor(NSAppleEventDescriptor(enumCode: Code.property), forKeyword: Code.keyForm)
        record.setDescriptor(NSAppleEventDescriptor(typeCode: property), forKeyword: Code.keyData)
        record.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: Code.container)
        return record.coerce(toDescriptorType: Code.objectSpecifier) ?? record
    }

    // MARK: - Reply decoding and error mapping (pure, unit-tested)

    static func playerState(fromReply reply: SpotifyReply) -> PlayerState {
        guard let code = reply.directObjectCode else { return .unknown }
        return playerState(fromEnumCode: code)
    }

    /// Spotify reports one less than the volume it was set to (set 50, read
    /// 49; measured for 1–99), so readings are corrected. Otherwise every
    /// fade that restores the volume it read would lower it by one.
    static func volume(fromReply reply: SpotifyReply) -> Int? {
        guard let reported = reply.directObjectInteger else { return nil }
        return (1...99).contains(reported) ? reported + 1 : min(max(reported, 0), 100)
    }

    static func playerState(fromEnumCode code: OSType) -> PlayerState {
        switch code {
        case Code.statePlaying: return .playing
        case Code.statePaused: return .paused
        case Code.stateStopped: return .stopped
        default: return .unknown
        }
    }

    /// An error Spotify reported inside an otherwise delivered reply.
    static func replyError(_ reply: NSAppleEventDescriptor) -> AutoHushError? {
        guard let number = reply.paramDescriptor(forKeyword: Code.errorNumber) else { return nil }
        let code = Int(number.int32Value)
        guard code != 0 else { return nil }
        let message = reply.paramDescriptor(forKeyword: Code.errorString)?.stringValue
        return mapError(number: code, message: message)
    }

    /// Maps an error thrown by `sendEvent` (an `NSOSStatusErrorDomain` error).
    static func mapError(_ error: any Error) -> AutoHushError {
        if let error = error as? AutoHushError { return error }
        let nsError = error as NSError
        return mapError(number: nsError.code, message: nil)
    }

    /// Maps an Apple event error number to a typed `AutoHushError`.
    static func mapError(number: Int, message: String?) -> AutoHushError {
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
struct SpotifyReply: Sendable, Equatable {
    /// Enum or type code of the reply's direct object (`----`), if any.
    let directObjectCode: OSType?
    /// The direct object as a number, if it is one (e.g. the volume).
    let directObjectInteger: Int?

    init(directObjectCode: OSType? = nil, directObjectInteger: Int? = nil) {
        self.directObjectCode = directObjectCode
        self.directObjectInteger = directObjectInteger
    }

    init(_ reply: NSAppleEventDescriptor) {
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
func fourCharCode(_ string: StaticString) -> OSType {
    precondition(string.utf8CodeUnitCount == 4, "four-char codes have exactly four bytes")
    return string.withUTF8Buffer { bytes in
        bytes.reduce(0) { ($0 << 8) | OSType($1) }
    }
}
