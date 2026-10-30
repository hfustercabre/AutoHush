import AppKit
import Foundation
import PlayersTestSupport
import Testing
@testable import ScriptablePlayers
import AutoHushKit
import AutoHushTestSupport

@Suite("ScriptablePlayer", .appleEventCoercions, .waitsTimeLimit)
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

    @Test("a truth value in the reply is read as one, not as a number; a real, a text and a list's items are read as such")
    func replyValues() {
        #expect(PlayerReply(reply(directObject: NSAppleEventDescriptor(boolean: true))).directObjectBoolean == true)
        let no = PlayerReply(reply(directObject: NSAppleEventDescriptor(boolean: false)))
        #expect(no.directObjectBoolean == false && no.directObjectInteger == nil && no.directObjectReal == nil)
        #expect(PlayerReply(reply(directObject: NSAppleEventDescriptor(int32: 1))).directObjectBoolean == nil)
        // QuickTime Player's: a document's audio volume; one document's name, or two documents' names and whether each plays.
        #expect(PlayerReply(reply(directObject: NSAppleEventDescriptor(double: 0.8))).directObjectReal == 0.8)
        let name = PlayerReply(reply(directObject: NSAppleEventDescriptor(string: "Song A")))
        #expect(name.directObjectText == "Song A" && name.listTexts.isEmpty)
        let names = NSAppleEventDescriptor.list()
        names.insert(NSAppleEventDescriptor(string: "Song A"), at: 1)
        names.insert(NSAppleEventDescriptor(string: "Song B"), at: 2)
        let flags = NSAppleEventDescriptor.list()
        flags.insert(NSAppleEventDescriptor(boolean: false), at: 1)
        flags.insert(NSAppleEventDescriptor(boolean: true), at: 2)
        #expect(PlayerReply(reply(directObject: names)).listTexts == ["Song A", "Song B"])
        #expect(PlayerReply(reply(directObject: flags)).listBooleans == [false, true])
        let none = PlayerReply(reply(directObject: NSAppleEventDescriptor.list())) // no document open
        #expect(none.listTexts.isEmpty && none.listBooleans.isEmpty && none.directObjectText == nil)
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

    @Test("errn in reply maps through the error table; errs, which can name what played, is left out")
    func replyWithError() {
        #expect(ScriptablePlayer.replyError(reply(errorNumber: -1743)) == .automationPermissionDenied)
        let error = ScriptablePlayer.replyError(reply(errorNumber: -1728, errorString: "Can’t get document \"Holiday.mov\"."))
        #expect(error == .playerCommandFailed(.appleEventError(-1728)))
        #expect(error?.logDescription.contains("Holiday") == false)
    }

    // MARK: - Error mapping

    @Test("sendEvent's NSError -1743 maps to automationPermissionDenied, procNotFound to playerNotRunning")
    func thrownErrors() {
        #expect(ScriptablePlayer.mapError(NSError(domain: NSOSStatusErrorDomain, code: -1743)) == .automationPermissionDenied)
        #expect(ScriptablePlayer.mapError(NSError(domain: NSOSStatusErrorDomain, code: -600)) == .playerNotRunning)
    }

    @Test("timeouts mean the app is not responding; other error numbers keep their OSStatus")
    func genericErrorCode() {
        let timeout = NSError(domain: NSOSStatusErrorDomain, code: -1712)

        #expect(ScriptablePlayer.mapError(timeout) == .playerNotResponding)
        #expect(ScriptablePlayer.mapError(number: -1708) == .playerCommandFailed(.appleEventError(-1708)))
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
            stateNotification: Notification.Name("com.example.jukebox.state"), volumeCurve: .cubic,
            iconPlaceholder: PlayerIconPlaceholder(tile: [.init(0x000000)], mark: .init(0x1ED760)) { CGMutablePath() }
        )
        let player = ScriptablePlayer(profile: profile)
        #expect(player.name == "Jukebox")
        #expect(player.bundleID == "com.example.jukebox")
        #expect(player.volumeCurve == .cubic)
        #expect(player.iconPlaceholder?.mark == .init(0x1ED760))
        #expect(player.stateReportDelay == 0) // its notification says each change at once
        #expect(profile.readVolume(42) == 42) // read as reported unless the profile says otherwise
    }

    /// The Jukebox's player, through `app` (by default, Apple events to the
    /// app, which isn't running), its volume read as `readVolume` says.
    private func jukeboxPlayer(_ app: FakeScriptedApp? = nil, readVolume: @escaping @Sendable (Int) -> Int = { $0 }) -> ScriptablePlayer {
        ScriptablePlayer(profile: ScriptablePlayerProfile(
            bundleID: "com.example.jukebox", name: "Jukebox", suite: fourCharCode("jbox"),
            stateNotification: Notification.Name("com.example.jukebox.state"), readVolume: readVolume
        ), channel: app)
    }

    @Test("running, the app is asked its state and volume, and sent its suite's pause and play")
    func sends() async throws {
        let app = FakeScriptedApp()
        let jukebox = jukeboxPlayer(app, readVolume: { $0 + 1 })
        try await jukebox.verifyControlAccess()
        #expect(await jukebox.playerState() == .playing)
        try await jukebox.pause()
        try await jukebox.play()
        #expect(await jukebox.volume() == 51) // read as the profile says
        try await jukebox.setVolume(150)
        #expect(app.sent == ["ask", "get pPlS", "get pPlS", "jboxPaus", "jboxPlay", "get pVol", "set pVol 100"])
    }

    @Test("an app that doesn't answer has its state unknown, and no volume")
    func unanswered() async {
        let jukebox = jukeboxPlayer(FakeScriptedApp { $0.fails = true })
        #expect(await jukebox.playerState() == .unknown)
        #expect(await jukebox.volume() == nil)
    }

    @Test("not running, the app isn't asked, and its commands and access check say so")
    func notRunning() async {
        let player = jukeboxPlayer()
        #expect(await player.playerState() == .notRunning)
        #expect(await player.volume() == nil)
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await player.verifyControlAccess() }
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await player.pause() }
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await player.play() }
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await player.setVolume(50) }
    }

    @MainActor
    @Test("a player watches its state through its notification")
    func observer() async {
        // A name of this run's own: nothing else posts it.
        let name = Notification.Name("com.example.jukebox.state.\(UUID().uuidString)")
        let profile = ScriptablePlayerProfile(bundleID: "com.example.jukebox", name: "Jukebox", suite: fourCharCode("jbox"),
                                              stateNotification: name)
        var states: [PlayerState] = []
        let observer = ScriptablePlayer(profile: profile).makeStateObserver { states.append($0) }
        #expect(observer is PlayerStateObserver)
        observer.start()
        defer { observer.stop() }
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: ["Player State": "Paused"],
                                                                     deliverImmediately: true)
        await TestWait.until { !states.isEmpty }
        #expect(states == [.paused])
    }
}
