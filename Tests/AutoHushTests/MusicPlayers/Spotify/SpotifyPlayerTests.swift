import AppKit
import Foundation
import Testing
@testable import AutoHush

@Suite("SpotifyPlayer")
struct SpotifyPlayerTests {

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
        let event = SpotifyPlayer.makeGetPlayerStateEvent(processIdentifier: pid)

        #expect(event.eventClass == fourCharCode("core"))
        #expect(event.eventID == fourCharCode("getd"))

        let specifier = try #require(event.paramDescriptor(forKeyword: fourCharCode("----")))
        #expect(specifier.descriptorType == fourCharCode("obj "))
        #expect(specifier.forKeyword(fourCharCode("want"))?.typeCodeValue == fourCharCode("prop"))
        #expect(specifier.forKeyword(fourCharCode("form"))?.enumCodeValue == fourCharCode("prop"))
        #expect(specifier.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("pPlS"))
        #expect(specifier.forKeyword(fourCharCode("from"))?.descriptorType == fourCharCode("null"))
    }

    @Test("volume is read with core/getd and set with core/setd on property pVol")
    func volumeEvents() throws {
        let get = SpotifyPlayer.makeGetVolumeEvent(processIdentifier: pid)
        #expect(get.eventClass == fourCharCode("core") && get.eventID == fourCharCode("getd"))
        #expect(get.paramDescriptor(forKeyword: fourCharCode("----"))?.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("pVol"))

        let set = SpotifyPlayer.makeSetVolumeEvent(42, processIdentifier: pid)
        #expect(set.eventClass == fourCharCode("core") && set.eventID == fourCharCode("setd"))
        #expect(set.paramDescriptor(forKeyword: fourCharCode("----"))?.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("pVol"))
        #expect(set.paramDescriptor(forKeyword: fourCharCode("data"))?.int32Value == 42)
    }

    @Test("Spotify's volume reading is corrected for its off-by-one", arguments: [
        (Int32(49), 50), (Int32(0), 0), (Int32(1), 2), (Int32(99), 100), (Int32(100), 100),
    ])
    func volumeReading(reported: Int32, volume: Int) {
        let answer = SpotifyReply(reply(directObject: NSAppleEventDescriptor(int32: reported)))
        #expect(SpotifyPlayer.volume(fromReply: answer) == volume)
    }

    @Test("a reply without a number has no volume")
    func volumeMissing() {
        #expect(SpotifyPlayer.volume(fromReply: SpotifyReply(reply())) == nil)
    }

    @Test("events target the given process, never a bundle ID that could launch Spotify")
    func eventsTargetProcessIdentifier() throws {
        let events = [
            SpotifyPlayer.makeGetPlayerStateEvent(processIdentifier: pid),
            SpotifyPlayer.makeCommandEvent(SpotifyPlayer.Code.pause, processIdentifier: pid),
        ]
        for event in events {
            let target = try #require(event.attributeDescriptor(forKeyword: fourCharCode("addr")))
            #expect(target.descriptorType == fourCharCode("kpid"))
            #expect(target.data == withUnsafeBytes(of: pid) { Data($0) })
        }
    }

    @Test("pause and play are spfy/Paus and spfy/Play without parameters")
    func commandEvents() {
        let pause = SpotifyPlayer.makeCommandEvent(SpotifyPlayer.Code.pause, processIdentifier: pid)
        let play = SpotifyPlayer.makeCommandEvent(SpotifyPlayer.Code.play, processIdentifier: pid)

        #expect(pause.eventClass == fourCharCode("spfy"))
        #expect(pause.eventID == fourCharCode("Paus"))
        #expect(play.eventClass == fourCharCode("spfy"))
        #expect(play.eventID == fourCharCode("Play"))
        #expect(pause.paramDescriptor(forKeyword: fourCharCode("----")) == nil)
    }

    // MARK: - Player state decoding

    @Test("ePlS enumerators map to PlayerState", arguments: [
        ("kPSP", PlayerState.playing),
        ("kPSp", PlayerState.paused),
        ("kPSS", PlayerState.stopped),
    ])
    func enumCodeMapping(code: String, expected: PlayerState) {
        let osType = code.utf8.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
        #expect(SpotifyPlayer.playerState(fromEnumCode: osType) == expected)
    }

    @Test("unknown enum code maps to unknown")
    func unknownEnumCode() {
        #expect(SpotifyPlayer.playerState(fromEnumCode: fourCharCode("kPSx")) == .unknown)
    }

    @Test("enumerated reply decodes to player state")
    func enumeratedReply() {
        let raw = reply(directObject: NSAppleEventDescriptor(enumCode: fourCharCode("kPSP")))

        let decoded = SpotifyReply(raw)

        #expect(decoded.directObjectCode == fourCharCode("kPSP"))
        #expect(SpotifyPlayer.playerState(fromReply: decoded) == .playing)
    }

    @Test("reply without direct object decodes to unknown")
    func missingDirectObject() {
        let decoded = SpotifyReply(reply())

        #expect(decoded.directObjectCode == nil)
        #expect(SpotifyPlayer.playerState(fromReply: decoded) == .unknown)
    }

    @Test("reply with a non-enum direct object decodes to unknown")
    func textDirectObject() {
        let decoded = SpotifyReply(reply(directObject: NSAppleEventDescriptor(string: "playing")))

        #expect(SpotifyPlayer.playerState(fromReply: decoded) == .unknown)
    }

    // MARK: - Reply errors

    @Test("successful reply carries no error")
    func replyWithoutError() {
        #expect(SpotifyPlayer.replyError(reply()) == nil)
        #expect(SpotifyPlayer.replyError(reply(errorNumber: 0)) == nil)
    }

    @Test("errn in reply maps through the error table, with errs as message")
    func replyWithError() {
        #expect(SpotifyPlayer.replyError(reply(errorNumber: -1743)) == .automationPermissionDenied)
        #expect(SpotifyPlayer.replyError(reply(errorNumber: -1708, errorString: "Not understood"))
                == .playerCommandFailed("Not understood (OSStatus -1708)"))
    }

    // MARK: - Error mapping

    @Test("-1743 error number maps to automationPermissionDenied")
    func automationDeniedErrorCode() {
        #expect(SpotifyPlayer.mapError(number: -1743, message: "Not authorized") == .automationPermissionDenied)
    }

    @Test("sendEvent NSError -1743 maps to automationPermissionDenied")
    func automationDeniedNSError() {
        let error = NSError(domain: NSOSStatusErrorDomain, code: -1743)

        #expect(SpotifyPlayer.mapError(error) == .automationPermissionDenied)
    }

    @Test("procNotFound maps to playerNotRunning")
    func processNotFound() {
        let error = NSError(domain: NSOSStatusErrorDomain, code: -600)

        #expect(SpotifyPlayer.mapError(error) == .playerNotRunning)
    }

    @Test("timeouts mean Spotify is not responding; other error numbers keep their OSStatus")
    func genericErrorCode() {
        let timeout = NSError(domain: NSOSStatusErrorDomain, code: -1712)

        #expect(SpotifyPlayer.mapError(timeout) == .playerNotResponding)
        #expect(SpotifyPlayer.mapError(number: -1708, message: "Spotify got an error")
                == .playerCommandFailed("Spotify got an error (OSStatus -1708)"))
    }

    @Test("empty message falls back to the bare OSStatus")
    func emptyMessage() {
        #expect(SpotifyPlayer.mapError(number: -50, message: "") == .playerCommandFailed("OSStatus -50"))
    }

    @Test("AutoHushError passes through unchanged")
    func passthrough() {
        #expect(SpotifyPlayer.mapError(AutoHushError.playerNotRunning) == .playerNotRunning)
    }
}
