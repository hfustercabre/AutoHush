import AppKit
import Foundation
import Testing
@testable import AutoHush

@Suite("SpotifyController")
struct SpotifyControllerTests {

    // Never sent: building descriptors does not contact the target process.
    private let pid: pid_t = 4242

    private func reply(directObject: NSAppleEventDescriptor? = nil,
                       errorNumber: Int32? = nil,
                       errorString: String? = nil) -> NSAppleEventDescriptor {
        let reply = NSAppleEventDescriptor.appleEvent(
            withEventClass: fourCharCode("aevt"),
            eventID: fourCharCode("ansr"),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if let directObject { reply.setParam(directObject, forKeyword: fourCharCode("----")) }
        if let errorNumber {
            reply.setParam(NSAppleEventDescriptor(int32: errorNumber), forKeyword: fourCharCode("errn"))
        }
        if let errorString {
            reply.setParam(NSAppleEventDescriptor(string: errorString), forKeyword: fourCharCode("errs"))
        }
        return reply
    }

    // MARK: - fourCharCode

    @Test("fourCharCode packs bytes big-endian")
    func fourCharCodePacking() {
        #expect(fourCharCode("core") == 0x636F_7265)
        #expect(fourCharCode("obj ") == OSType(typeObjectSpecifier))
        #expect(fourCharCode("----") == OSType(keyDirectObject))
    }

    // MARK: - Event construction

    @Test("player state event is core/getd on property pPlS of application")
    func getPlayerStateEvent() throws {
        let event = SpotifyController.makeGetPlayerStateEvent(processIdentifier: pid)

        #expect(event.eventClass == fourCharCode("core"))
        #expect(event.eventID == fourCharCode("getd"))

        let specifier = try #require(event.paramDescriptor(forKeyword: fourCharCode("----")))
        #expect(specifier.descriptorType == fourCharCode("obj "))
        #expect(specifier.forKeyword(fourCharCode("want"))?.typeCodeValue == fourCharCode("prop"))
        #expect(specifier.forKeyword(fourCharCode("form"))?.enumCodeValue == fourCharCode("prop"))
        #expect(specifier.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("pPlS"))
        #expect(specifier.forKeyword(fourCharCode("from"))?.descriptorType == fourCharCode("null"))
    }

    @Test("events target the given process, never a bundle ID that could launch Spotify")
    func eventsTargetProcessIdentifier() throws {
        let events = [
            SpotifyController.makeGetPlayerStateEvent(processIdentifier: pid),
            SpotifyController.makeCommandEvent(SpotifyController.Code.pause, processIdentifier: pid),
        ]
        for event in events {
            let target = try #require(event.attributeDescriptor(forKeyword: fourCharCode("addr")))
            #expect(target.descriptorType == fourCharCode("kpid"))
            #expect(target.data == withUnsafeBytes(of: pid) { Data($0) })
        }
    }

    @Test("pause and play are spfy/Paus and spfy/Play without parameters")
    func commandEvents() {
        let pause = SpotifyController.makeCommandEvent(SpotifyController.Code.pause, processIdentifier: pid)
        let play = SpotifyController.makeCommandEvent(SpotifyController.Code.play, processIdentifier: pid)

        #expect(pause.eventClass == fourCharCode("spfy"))
        #expect(pause.eventID == fourCharCode("Paus"))
        #expect(play.eventClass == fourCharCode("spfy"))
        #expect(play.eventID == fourCharCode("Play"))
        #expect(pause.paramDescriptor(forKeyword: fourCharCode("----")) == nil)
    }

    // MARK: - Player state decoding

    @Test("ePlS enumerators map to SpotifyPlayerState", arguments: [
        ("kPSP", SpotifyPlayerState.playing),
        ("kPSp", SpotifyPlayerState.paused),
        ("kPSS", SpotifyPlayerState.stopped),
    ])
    func enumCodeMapping(code: String, expected: SpotifyPlayerState) {
        let osType = code.utf8.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
        #expect(SpotifyController.playerState(fromEnumCode: osType) == expected)
    }

    @Test("unknown enum code maps to unknown")
    func unknownEnumCode() {
        #expect(SpotifyController.playerState(fromEnumCode: fourCharCode("kPSx")) == .unknown)
    }

    @Test("enumerated reply decodes to player state")
    func enumeratedReply() {
        let raw = reply(directObject: NSAppleEventDescriptor(enumCode: fourCharCode("kPSP")))

        let decoded = SpotifyReply(raw)

        #expect(decoded.directObjectCode == fourCharCode("kPSP"))
        #expect(SpotifyController.playerState(fromReply: decoded) == .playing)
    }

    @Test("reply without direct object decodes to unknown")
    func missingDirectObject() {
        let decoded = SpotifyReply(reply())

        #expect(decoded.directObjectCode == nil)
        #expect(SpotifyController.playerState(fromReply: decoded) == .unknown)
    }

    @Test("reply with a non-enum direct object decodes to unknown")
    func textDirectObject() {
        let decoded = SpotifyReply(reply(directObject: NSAppleEventDescriptor(string: "playing")))

        #expect(SpotifyController.playerState(fromReply: decoded) == .unknown)
    }

    // MARK: - Reply errors

    @Test("successful reply carries no error")
    func replyWithoutError() {
        #expect(SpotifyController.replyError(reply()) == nil)
        #expect(SpotifyController.replyError(reply(errorNumber: 0)) == nil)
    }

    @Test("errn in reply maps through the error table, with errs as message")
    func replyWithError() {
        #expect(SpotifyController.replyError(reply(errorNumber: -1743)) == .automationPermissionDenied)
        #expect(SpotifyController.replyError(reply(errorNumber: -1708, errorString: "Not understood"))
                == .spotifyCommandFailed("Not understood (OSStatus -1708)"))
    }

    // MARK: - Error mapping

    @Test("-1743 error number maps to automationPermissionDenied")
    func automationDeniedErrorCode() {
        #expect(SpotifyController.mapError(number: -1743, message: "Not authorized") == .automationPermissionDenied)
    }

    @Test("sendEvent NSError -1743 maps to automationPermissionDenied")
    func automationDeniedNSError() {
        let error = NSError(domain: NSOSStatusErrorDomain, code: -1743)

        #expect(SpotifyController.mapError(error) == .automationPermissionDenied)
    }

    @Test("procNotFound maps to spotifyUnavailable")
    func processNotFound() {
        let error = NSError(domain: NSOSStatusErrorDomain, code: -600)

        #expect(SpotifyController.mapError(error) == .spotifyUnavailable)
    }

    @Test("other error numbers map to spotifyCommandFailed with the OSStatus")
    func genericErrorCode() {
        let timeout = NSError(domain: NSOSStatusErrorDomain, code: -1712)

        #expect(SpotifyController.mapError(timeout) == .spotifyCommandFailed("OSStatus -1712"))
        #expect(SpotifyController.mapError(number: -1708, message: "Spotify got an error")
                == .spotifyCommandFailed("Spotify got an error (OSStatus -1708)"))
    }

    @Test("empty message falls back to the bare OSStatus")
    func emptyMessage() {
        #expect(SpotifyController.mapError(number: -50, message: "") == .spotifyCommandFailed("OSStatus -50"))
    }

    @Test("AutoHushError passes through unchanged")
    func passthrough() {
        #expect(SpotifyController.mapError(AutoHushError.spotifyUnavailable) == .spotifyUnavailable)
    }
}
