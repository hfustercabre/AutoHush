import Testing
@testable import PlayerCheckKit

@Suite("Sign")
struct SignTests {
    @Test("a look's surest sign: the scripted state, Now Playing's report, the page's current word, the level, the keep-awake assertion, the menu; stopped by the first, the report or the menu; a press judged by the surest sign before it, else by the menu's word or the sound")
    func signs() {
        let everything = Look(menuTitle: "Pause", menuState: .playing, state: .paused, reported: "Playing", pageToggle: "Pause",
                              pageSays: .playing, sounding: true, audible: true, awake: true)
        #expect(everything.surest == .script && everything.says(.script) == .paused && everything.says(.report) == .playing)
        // A page's word out of sight, or one it doesn't know, says nothing.
        var page = Look(pageToggle: "Pausa", pageSays: .playing, pageCurrent: false, sounding: true, awake: false)
        #expect(page.says(.page) == nil && page.surest == .awake)
        page.pageCurrent = true
        #expect(page.surest == .page)
        page.pageSays = nil
        #expect(page.says(.page) == nil)
        #expect(Look(menuState: .stopped, sounding: false).stopped)
        #expect(!Look(menuState: .stopped, reported: "Paused", sounding: false).stopped) // the report is surer
        #expect(Look(reported: "Stopped", sounding: false).stopped && !Look(sounding: false, audible: false).stopped)

        let heard = Sign(before: Look(sounding: true, audible: true))
        #expect(heard.kind == .level && heard.byLevel)
        #expect(heard.paused(Look(sounding: true, audible: false)) && !heard.paused(Look(sounding: false))) // unmeasured: no answer
        #expect(heard.playing(Look(sounding: true, audible: true)) && !heard.playing(Look(sounding: true)))
        // Nothing sure before the press: its menu's word changing, or its sound closing, tells.
        let blind = Sign(before: Look(menuTitle: "Pause", sounding: true))
        #expect(blind.kind == nil && !blind.byLevel)
        #expect(blind.paused(Look(menuTitle: "Play", sounding: true)) && blind.paused(Look(menuTitle: "Pause", sounding: false)))
        #expect(!blind.paused(Look(menuTitle: "Pause", sounding: true)))
        #expect(blind.playing(Look(sounding: true)) && !blind.playing(Look(sounding: false)))
    }
}
