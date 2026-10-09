import AppKit
import Foundation
import Testing
@testable import ScriptablePlayers
import AutoHushKit

@Suite("ScriptablePlayer")
struct ScriptablePlayerTests {

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
        let event = ScriptablePlayer.makeGetPlayerStateEvent(processIdentifier: pid)

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
        let get = ScriptablePlayer.makeGetVolumeEvent(processIdentifier: pid)
        #expect(get.eventClass == fourCharCode("core") && get.eventID == fourCharCode("getd"))
        #expect(get.paramDescriptor(forKeyword: fourCharCode("----"))?.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("pVol"))

        let set = ScriptablePlayer.makeSetVolumeEvent(42, processIdentifier: pid)
        #expect(set.eventClass == fourCharCode("core") && set.eventID == fourCharCode("setd"))
        #expect(set.paramDescriptor(forKeyword: fourCharCode("----"))?.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("pVol"))
        #expect(set.paramDescriptor(forKeyword: fourCharCode("data"))?.int32Value == 42)
    }

    @Test("the volume read is corrected as the profile says, and kept within 0–100", arguments: [
        (Int32(49), 50), (Int32(0), 1), (Int32(100), 100), (Int32(-3), 0), (Int32(150), 100),
    ])
    func volumeReading(reported: Int32, volume: Int) {
        let answer = PlayerReply(reply(directObject: NSAppleEventDescriptor(int32: reported)))
        #expect(ScriptablePlayer.volume(fromReply: answer, reading: { $0 + 1 }) == volume)
    }

    @Test("a truth value in the reply is read as one, not as a number")
    func booleanReply() {
        #expect(PlayerReply(reply(directObject: NSAppleEventDescriptor(boolean: true))).directObjectBoolean == true)
        let no = PlayerReply(reply(directObject: NSAppleEventDescriptor(boolean: false)))
        #expect(no.directObjectBoolean == false && no.directObjectInteger == nil)
        #expect(PlayerReply(reply(directObject: NSAppleEventDescriptor(int32: 1))).directObjectBoolean == nil)
    }

    @Test("any property of the application can be set to a number")
    func setPropertyEvent() {
        let set = ScriptablePlayer.makeSetPropertyEvent(fourCharCode("AAAV"), to: 300, processIdentifier: pid)
        #expect(set.eventClass == fourCharCode("core") && set.eventID == fourCharCode("setd"))
        #expect(set.paramDescriptor(forKeyword: fourCharCode("----"))?.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("AAAV"))
        #expect(set.paramDescriptor(forKeyword: fourCharCode("data"))?.int32Value == 300)
    }

    @Test("a reply without a number has no volume")
    func volumeMissing() {
        #expect(ScriptablePlayer.volume(fromReply: PlayerReply(reply()), reading: { $0 }) == nil)
    }

    @Test("events target the given process, never a bundle ID that could launch the app")
    func eventsTargetProcessIdentifier() throws {
        let events = [
            ScriptablePlayer.makeGetPlayerStateEvent(processIdentifier: pid),
            ScriptablePlayer.makeCommandEvent(suite: fourCharCode("jbox"), ScriptablePlayer.Code.pause, processIdentifier: pid),
        ]
        for event in events {
            let target = try #require(event.attributeDescriptor(forKeyword: fourCharCode("addr")))
            #expect(target.descriptorType == fourCharCode("kpid"))
            #expect(target.data == withUnsafeBytes(of: pid) { Data($0) })
        }
    }

    @Test("pause and play are Paus and Play of the app's own suite, without parameters")
    func commandEvents() {
        let pause = ScriptablePlayer.makeCommandEvent(suite: fourCharCode("jbox"), ScriptablePlayer.Code.pause, processIdentifier: pid)
        let play = ScriptablePlayer.makeCommandEvent(suite: fourCharCode("jbox"), ScriptablePlayer.Code.play, processIdentifier: pid)

        #expect(pause.eventClass == fourCharCode("jbox"))
        #expect(pause.eventID == fourCharCode("Paus"))
        #expect(play.eventClass == fourCharCode("jbox"))
        #expect(play.eventID == fourCharCode("Play"))
        #expect(pause.paramDescriptor(forKeyword: fourCharCode("----")) == nil)
    }

    // MARK: - Player state decoding

    @Test("ePlS enumerators map to PlayerState; seeking counts as playing", arguments: [
        ("kPSP", PlayerState.playing),
        ("kPSp", PlayerState.paused),
        ("kPSS", PlayerState.stopped),
        ("kPSF", PlayerState.playing),
        ("kPSR", PlayerState.playing),
    ])
    func enumCodeMapping(code: String, expected: PlayerState) {
        let osType = code.utf8.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
        #expect(ScriptablePlayer.playerState(fromEnumCode: osType) == expected)
    }

    @Test("unknown enum code maps to unknown")
    func unknownEnumCode() {
        #expect(ScriptablePlayer.playerState(fromEnumCode: fourCharCode("kPSx")) == .unknown)
    }

    @Test("enumerated reply decodes to player state")
    func enumeratedReply() {
        let raw = reply(directObject: NSAppleEventDescriptor(enumCode: fourCharCode("kPSP")))

        let decoded = PlayerReply(raw)

        #expect(decoded.directObjectCode == fourCharCode("kPSP"))
        #expect(ScriptablePlayer.playerState(fromReply: decoded) == .playing)
    }

    @Test("reply without direct object decodes to unknown")
    func missingDirectObject() {
        let decoded = PlayerReply(reply())

        #expect(decoded.directObjectCode == nil)
        #expect(ScriptablePlayer.playerState(fromReply: decoded) == .unknown)
    }

    @Test("reply with a non-enum direct object decodes to unknown")
    func textDirectObject() {
        let decoded = PlayerReply(reply(directObject: NSAppleEventDescriptor(string: "playing")))

        #expect(ScriptablePlayer.playerState(fromReply: decoded) == .unknown)
    }

    // MARK: - Reply errors

    @Test("successful reply carries no error")
    func replyWithoutError() {
        #expect(ScriptablePlayer.replyError(reply()) == nil)
        #expect(ScriptablePlayer.replyError(reply(errorNumber: 0)) == nil)
    }

    @Test("errn in reply maps through the error table, with errs as message")
    func replyWithError() {
        #expect(ScriptablePlayer.replyError(reply(errorNumber: -1743)) == .automationPermissionDenied)
        #expect(ScriptablePlayer.replyError(reply(errorNumber: -1708, errorString: "Not understood"))
                == .playerCommandFailed(.appleEventError(-1708, message: "Not understood")))
    }

    // MARK: - Error mapping

    @Test("-1743 error number maps to automationPermissionDenied")
    func automationDeniedErrorCode() {
        #expect(ScriptablePlayer.mapError(number: -1743, message: "Not authorized") == .automationPermissionDenied)
    }

    @Test("sendEvent NSError -1743 maps to automationPermissionDenied")
    func automationDeniedNSError() {
        let error = NSError(domain: NSOSStatusErrorDomain, code: -1743)

        #expect(ScriptablePlayer.mapError(error) == .automationPermissionDenied)
    }

    @Test("procNotFound maps to playerNotRunning")
    func processNotFound() {
        let error = NSError(domain: NSOSStatusErrorDomain, code: -600)

        #expect(ScriptablePlayer.mapError(error) == .playerNotRunning)
    }

    @Test("timeouts mean the app is not responding; other error numbers keep their OSStatus")
    func genericErrorCode() {
        let timeout = NSError(domain: NSOSStatusErrorDomain, code: -1712)

        #expect(ScriptablePlayer.mapError(timeout) == .playerNotResponding)
        #expect(ScriptablePlayer.mapError(number: -1708, message: "The app got an error")
                == .playerCommandFailed(.appleEventError(-1708, message: "The app got an error")))
    }

    @Test("empty message falls back to the bare OSStatus")
    func emptyMessage() {
        #expect(ScriptablePlayer.mapError(number: -50, message: "") == .playerCommandFailed(.appleEventError(-50, message: nil)))
    }

    @Test("MusicPlayerError passes through unchanged")
    func passthrough() {
        #expect(ScriptablePlayer.mapError(MusicPlayerError.playerNotRunning) == .playerNotRunning)
    }

    // MARK: - The player

    @Test("a player is named, identified and fades as its profile says")
    func identity() {
        let profile = ScriptablePlayerProfile(
            bundleID: "com.example.jukebox", name: "Jukebox", suite: fourCharCode("jbox"),
            stateNotification: Notification.Name("com.example.jukebox.state"), volumeCurve: .cubic
        )
        let player = ScriptablePlayer(profile: profile)
        #expect(player.name == "Jukebox")
        #expect(player.bundleID == "com.example.jukebox")
        #expect(player.volumeCurve == .cubic)
        #expect(profile.readVolume(42) == 42) // read as reported unless the profile says otherwise
    }

    @MainActor
    @Test("a player watches its state through its notification")
    func observer() {
        let profile = ScriptablePlayerProfile(
            bundleID: "com.example.jukebox", name: "Jukebox", suite: fourCharCode("jbox"),
            stateNotification: Notification.Name("com.example.jukebox.state")
        )
        #expect(ScriptablePlayer(profile: profile).makeStateObserver { _ in } is PlayerStateObserver)
    }
}
