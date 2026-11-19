import AppKit
import Testing
@testable import PlayerCheck
@testable import ScriptablePlayers

/// The check's AppleScript, chosen as AutoHush chooses it (`ScriptSetup`).
@Suite("playercheck: its AppleScript", .readOnlyRun)
struct ScriptControlsTests {
    private func dictionary(_ xml: String) throws -> Scripting {
        try #require(Scripting.parse(XMLDocument(xmlString: xml)))
    }

    @Test("pause and play in its own suite, by code, named as its dictionary names them")
    func ownSuite() throws {
        let scripting = try dictionary("""
            <dictionary><suite name="Streamer Suite" code="strm">
              <command name="pause" code="strmPaus"/><command name="play" code="strmPlay"/><command name="playpause" code="strmPlPs"/>
            </suite></dictionary>
            """)
        let controls = try #require(scriptControls(of: scripting))
        #expect(controls.pause == ScriptCommand(code: "strmPaus", name: "pause", pauses: true))
        #expect(controls.play == ScriptCommand(code: "strmPlay", name: "play", pauses: false))
        #expect(!controls.toggles)
    }

    @Test("one that toggles is sent both ways, the code AutoHush keeps; none without play or pause")
    func toggles() throws {
        let scripting = try dictionary("""
            <dictionary><suite name="Jukebox" code="juke"><command name="PlayPause" code="jukeTogl"/></suite></dictionary>
            """)
        let controls = try #require(scriptControls(of: scripting))
        #expect(controls.toggles)
        #expect(controls.pause == ScriptCommand(code: "jukeTogl", name: "PlayPause", pauses: true))
        #expect(controls.play == ScriptCommand(code: "jukeTogl", name: "PlayPause", pauses: false))
        #expect(scriptControls(of: try dictionary("""
            <dictionary><suite name="Standard" code="core"><command name="open" code="aevtodoc"/></suite></dictionary>
            """)) == nil)
        #expect(scriptControls(of: nil) == nil)
    }

    @Test("its volume checked: its sound volume, else its audio volume, the first by code when two are named so, whatever the dictionary's order")
    func volume() {
        var scripting = Scripting()
        scripting.properties = ["zzzzVol2": "audio volume", "pVol": "sound volume", "aVol": "sound volume", "pPlS": "player state"]
        #expect(volumeProperty(of: scripting).map { [$0.code, $0.name] } == ["aVol", "sound volume"])
        scripting.properties = ["zzzzVol2": "audio volume", "bbbbVol1": "audio volume"]
        #expect(volumeProperty(of: scripting).map { [$0.code, $0.name] } == ["bbbbVol1", "audio volume"])
        scripting.properties = ["pPlS": "player state"]
        #expect(volumeProperty(of: scripting) == nil)
    }

    @Test("to documents as AutoHush sends it: a pause to each one playing (then in hand), a play to those still open, kept for a play again; else only to the one open, never the front one of several (playercheck-2)")
    func documentTargets() {
        let both = [(name: "A", playing: false), (name: "B", playing: true)]
        var paused: [String] = []
        #expect(scriptTargets(pauses: true, among: both, paused: &paused) == ["B"])
        #expect(paused == ["B"])
        let stopped = [(name: "A", playing: false), (name: "B", playing: false)]
        #expect(scriptTargets(pauses: false, among: stopped, paused: &paused) == ["B"])
        // The play didn't take: pressed once more, it still goes to B.
        #expect(scriptTargets(pauses: false, among: stopped, paused: &paused) == ["B"])
        // A pause with nothing playing keeps those in hand.
        #expect(scriptTargets(pauses: true, among: stopped, paused: &paused).isEmpty)
        #expect(paused == ["B"])

        var none: [String] = []
        #expect(scriptTargets(pauses: false, among: stopped, paused: &none).isEmpty)
        #expect(scriptTargets(pauses: false, among: [(name: "A", playing: false)], paused: &none) == ["A"])
        #expect(scriptTargets(pauses: false, among: [], paused: &none).isEmpty)
    }
}
