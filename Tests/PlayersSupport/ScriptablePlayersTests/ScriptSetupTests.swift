import AppKit
import Foundation
import Testing
@testable import ScriptablePlayers
import AutoHushTestSupport

@Suite("ScriptSetup")
struct ScriptSetupTests {
    private func dictionary(_ xml: String) throws -> ScriptingDictionary {
        try #require(ScriptingDictionary.parse(XMLDocument(xmlString: xml)))
    }

    /// Spotify's, cut down: pause and play in its own suite, player state, sound volume.
    private let spotify = """
        <dictionary><suite name="Spotify Suite" code="spfy">
          <command name="pause" code="spfyPaus"/><command name="play" code="spfyPlay"/>
          <command name="playpause" code="spfyPlPs"/>
          <class name="application" code="capp">
            <property name="player state" code="pPlS"/><property name="sound volume" code="pVol"/>
            <property name="current track" code="pTrk"/>
          </class>
          <enumeration name="ePlS" code="ePlS">
            <enumerator name="stopped" code="kPSS"/><enumerator name="playing" code="kPSP"/><enumerator name="paused" code="kPSp"/>
          </enumeration>
        </suite></dictionary>
        """

    /// VLC's, cut down: a play that toggles, a playing flag and a current time.
    private let vlc = """
        <dictionary><suite name="VLC suite" code="VLC ">
          <command name="play" code="VLC play"/><command name="stop" code="VLC stop"/>
          <class-extension extends="application">
            <property name="playing" code="Plng"/><property name="current time" code="pos "/>
          </class-extension>
        </suite></dictionary>
        """

    /// QuickTime Player's, cut down: play and pause act on a document, each with its own `playing`.
    private let quickTime = """
        <dictionary><suite name="QuickTime Player Suite" code="MVWR">
          <command name="play" code="MVWRplay"><direct-parameter type="document"/></command>
          <command name="pause" code="MVWRpaus"><direct-parameter type="document"/></command>
          <class-extension extends="document">
            <property name="playing" code="splg"/>
          </class-extension>
        </suite></dictionary>
        """

    @Test("an app with pause and play in its own suite and a player state: as Spotify's profile")
    func ownSuite() throws {
        let dictionary = try dictionary(spotify)
        #expect(dictionary.suite == "spfy")
        #expect(dictionary.fitsScriptablePlayer)
        let setup = try #require(ScriptSetup(dictionary: dictionary))
        #expect(setup == ScriptSetup(commands: .pauseAndPlay(pause: "spfyPaus", play: "spfyPlay"), state: .playerState, hasVolume: true))
    }

    @Test("an app with only a play that toggles, and a playing flag: toggled from the opposite state; with a playpause and no state, by its other signs")
    func toggles() throws {
        let setup = try #require(ScriptSetup(dictionary: dictionary(vlc)))
        #expect(setup.commands == .toggle("VLC play"))
        #expect(setup.state == .playingFlag(property: "Plng", currentTime: "pos "))
        #expect(!setup.actsOnDocuments)
        #expect(!setup.hasVolume)
        let stateless = try #require(ScriptSetup(dictionary: dictionary("""
            <dictionary><suite name="Jukebox" code="juke"><command name="playpause" code="jukeTogl"/></suite></dictionary>
            """)))
        #expect(stateless.commands == .toggle("jukeTogl"))
        #expect(stateless.state == nil)
    }

    @Test("an app whose play and pause act on a document, each with its own playing: by its documents")
    func documents() throws {
        let dictionary = try dictionary(quickTime)
        #expect(dictionary.playsDocuments)
        #expect(dictionary.documentClass == "docu")
        let setup = try #require(ScriptSetup(dictionary: dictionary))
        #expect(setup.commands == .pauseAndPlay(pause: "MVWRpaus", play: "MVWRplay"))
        #expect(setup.actsOnDocuments)
        #expect(setup.state == .documents(documentClass: "docu", playing: "splg"))
    }

    @Test("an app's dictionary is read from its bundle: the .sdef its Info.plist names, else the first in its resources that has one; not running, it's never asked for one")
    func readFromBundle() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScriptSetupTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        /// An app holding `files` (name: text) in its resources, its Info.plist naming `named`.
        func app(_ name: String, named: String? = nil, files: [String: String]) throws -> URL {
            let info = ["CFBundleIdentifier": "com.example.\(name.lowercased())", "OSAScriptingDefinition": named].compactMapValues { $0 }
            return try TestAppBundle.make(in: folder, name: name, info: info, resources: files)
        }
        // Named without its extension, as many apps name it; the other .sdef isn't read.
        let named = try ScriptingDictionary.read(appAt: app("Spotify", named: "Spotify", files: ["Spotify.sdef": spotify, "Other.sdef": vlc]),
                                                 isRunning: false)
        #expect(named?.suite == "spfy")
        #expect(named.map { $0.hasState && $0.namesItsSong } == true)
        // Not named: the first that holds a dictionary.
        let itemNamed = vlc.replacingOccurrences(of: "</class-extension>", with: "<property name=\"name of current item\" code=\"nmci\"/></class-extension>")
        let found = try ScriptingDictionary.read(appAt: app("VLC", files: ["A.sdef": "<dictionary/>", "B.sdef": itemNamed]), isRunning: false)
        #expect(found?.hasPlayingFlag == true && found?.hasState == true)
        #expect(found?.currentItemName == "nmci" && found?.namesItsSong == true)
        // Only old .scriptSuite files: only the running app could say, so nothing is read;
        // running, `sdef` is asked, and finds nothing either (there's no program to ask).
        let old = try app("Old", files: ["Old.scriptSuite": "{}"])
        #expect(ScriptingDictionary.isInBundle(at: old))
        #expect(ScriptingDictionary.read(appAt: old, isRunning: false) == nil)
        #expect(ScriptingDictionary.read(appAt: old, isRunning: true) == nil)
    }

    @Test("its state is read where AutoHush reads it: player state only with its three values, else its playing flag, else none; also without commands")
    func stateAsAutoHushReadsIt() throws {
        // A player state of its own values, and a playing flag: the flag.
        let ownValues = try dictionary("""
            <dictionary><suite name="Jukebox" code="juke">
              <command name="pause" code="jukePaus"/><command name="play" code="jukePlay"/>
              <class name="application" code="capp">
                <property name="player state" code="pPlS"/><property name="playing" code="jPlg"/>
              </class>
              <enumeration name="eSta" code="eSta"><enumerator name="spinning" code="jSpn"/></enumeration>
            </suite></dictionary>
            """)
        #expect(ownValues.hasPlayerState && !ownValues.hasStateValues)
        #expect(ScriptSetup.State(dictionary: ownValues) == .playingFlag(property: "jPlg", currentTime: nil))
        #expect(ScriptSetup(dictionary: ownValues)?.state == .playingFlag(property: "jPlg", currentTime: nil))
        #expect(ownValues.hasState)
        // Its own values only: no state AutoHush can read, so none for Player Check either.
        let unreadable = try dictionary("""
            <dictionary><suite name="Jukebox" code="juke">
              <command name="playpause" code="jukeTogl"/>
              <class name="application" code="capp"><property name="player state" code="pPlS"/></class>
              <enumeration name="eSta" code="eSta"><enumerator name="spinning" code="jSpn"/></enumeration>
            </suite></dictionary>
            """)
        #expect(ScriptSetup.State(dictionary: unreadable) == nil)
        #expect(ScriptSetup(dictionary: unreadable)?.state == nil)
        #expect(!unreadable.hasState)
        // A state, and no command: read all the same.
        let stateOnly = try dictionary(spotify.replacingOccurrences(of: #"<command name="pause" code="spfyPaus"/><command name="play" code="spfyPlay"/>"#, with: "")
            .replacingOccurrences(of: #"<command name="playpause" code="spfyPlPs"/>"#, with: ""))
        #expect(ScriptSetup(dictionary: stateOnly) == nil)
        #expect(ScriptSetup.State(dictionary: stateOnly) == .playerState)
    }

    @Test("an app with no play or pause can't be scripted")
    func nothingToPress() throws {
        let dictionary = try dictionary("""
            <dictionary><suite name="Standard" code="core"><command name="open" code="aevtodoc"/></suite></dictionary>
            """)
        #expect(ScriptSetup(dictionary: dictionary) == nil)
    }

    @Test("a setup is kept as it was found")
    func kept() throws {
        let setup = try #require(ScriptSetup(dictionary: dictionary(quickTime)))
        let decoded = try JSONDecoder().decode(ScriptSetup.self, from: JSONEncoder().encode(setup))
        #expect(decoded == setup)
    }

    @Test("its events: the codes read as text, sent to a document when they act on one")
    func events() {
        #expect(ScriptedAppPlayer.code("spfy") == fourCharCode("spfy"))
        let pause = ScriptedAppPlayer.makeCommandEvent("spfyPaus", processIdentifier: 4242)
        #expect(pause.eventClass == fourCharCode("spfy"))
        #expect(pause.eventID == fourCharCode("Paus"))
        #expect(pause.paramDescriptor(forKeyword: ScriptablePlayer.Code.directObject) == nil)

        let named = ScriptedAppPlayer.documentSpecifier("docu", named: "Song.m4a")
        let play = ScriptedAppPlayer.makeCommandEvent("MVWRplay", to: named, processIdentifier: 4242)
        let target = play.paramDescriptor(forKeyword: ScriptablePlayer.Code.directObject)
        #expect(target?.forKeyword(ScriptablePlayer.Code.keyData)?.stringValue == "Song.m4a")
        #expect(target?.forKeyword(ScriptablePlayer.Code.desiredClass)?.typeCodeValue == fourCharCode("docu"))
        let every = ScriptedAppPlayer.documentSpecifier("docu")
        #expect(every.forKeyword(ScriptablePlayer.Code.keyData)?.descriptorType == fourCharCode("abso"))
        // "document 1", the front one, as Player Check plays one when it paused none.
        let front = ScriptedAppPlayer.documentSpecifier("docu", index: 1)
        #expect(front.forKeyword(ScriptablePlayer.Code.keyForm)?.enumCodeValue == fourCharCode("indx"))
        #expect(front.forKeyword(ScriptablePlayer.Code.keyData)?.int32Value == 1)
        #expect(front.forKeyword(ScriptablePlayer.Code.desiredClass)?.typeCodeValue == fourCharCode("docu"))
    }
}
