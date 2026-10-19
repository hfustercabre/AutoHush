import AppKit
import Testing
@testable import PlayerCheck

/// The check's AppleScript, chosen as AutoHush chooses it (`ScriptSetup`).
@Suite("playercheck: its AppleScript")
struct ScriptControlsTests {
    private func dictionary(_ xml: String) throws -> Scripting {
        try #require(Scripting.parse(XMLDocument(xmlString: xml)))
    }

    @Test("pause and play in its own suite, by code, named as its dictionary names them")
    func ownSuite() throws {
        let scripting = try dictionary("""
            <dictionary><suite name="Spotify Suite" code="spfy">
              <command name="pause" code="spfyPaus"/><command name="play" code="spfyPlay"/><command name="playpause" code="spfyPlPs"/>
            </suite></dictionary>
            """)
        let controls = try #require(scriptControls(of: scripting))
        #expect(controls.pause == ScriptCommand(code: "spfyPaus", name: "pause", pauses: true))
        #expect(controls.play == ScriptCommand(code: "spfyPlay", name: "play", pauses: false))
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
}
