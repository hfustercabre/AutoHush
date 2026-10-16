import AppKit
import Foundation
import Testing
@testable import ScriptablePlayers
import AutoHushKit

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

    @Test("an app with only a play that toggles, and a playing flag: toggled from the opposite state")
    func toggles() throws {
        let setup = try #require(ScriptSetup(dictionary: dictionary(vlc)))
        #expect(setup.commands == .toggle("VLC play"))
        #expect(setup.state == .playingFlag(property: "Plng", currentTime: "pos "))
        #expect(!setup.actsOnDocuments)
        #expect(!setup.hasVolume)
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
            let url = folder.appendingPathComponent("\(name).app")
            let resources = url.appendingPathComponent("Contents/Resources")
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            try (["CFBundleIdentifier": "com.example.\(name.lowercased())", "OSAScriptingDefinition": named].compactMapValues { $0 } as NSDictionary)
                .write(to: url.appendingPathComponent("Contents/Info.plist"))
            for (file, text) in files { try Data(text.utf8).write(to: resources.appendingPathComponent(file)) }
            return url
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
        // Only old .scriptSuite files: only the running app could say, so nothing is read.
        let old = try app("Old", files: ["Old.scriptSuite": "{}"])
        #expect(ScriptingDictionary.isInBundle(at: old))
        #expect(ScriptingDictionary.read(appAt: old, isRunning: false) == nil)
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
        let front = ScriptedAppPlayer.documentSpecifier("docu", named: .some(nil))
        #expect(front.forKeyword(ScriptablePlayer.Code.keyData)?.int32Value == 1)
    }
}
