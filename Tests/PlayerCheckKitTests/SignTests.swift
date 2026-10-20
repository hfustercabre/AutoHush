import AutoHushKit
import Testing
@testable import PlayerCheckKit

@Suite("Sign")
struct SignTests {
    @Test("a look's surest sign: the scripted state, Now Playing's report, the page's current word, the level, the keep-awake assertion, the menu")
    func surestSign() {
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
    }

    @Test("a look is stopped as its scripted state says, else Now Playing's report, else the menu")
    func stopped() {
        #expect(Look(menuState: .stopped, sounding: false).stopped)
        #expect(!Look(menuState: .stopped, reported: "Paused", sounding: false).stopped) // the report is surer
        #expect(Look(reported: "Stopped", sounding: false).stopped && !Look(sounding: false, audible: false).stopped)
    }

    @Test("a press is judged by the surest sign before it")
    func pressJudgedBySurestSign() {
        let heard = Sign(before: Look(sounding: true, audible: true))
        #expect(heard.kind == .level && heard.byLevel)
        #expect(heard.paused(Look(sounding: true, audible: false)) && !heard.paused(Look(sounding: false))) // unmeasured: no answer
        #expect(heard.playing(Look(sounding: true, audible: true)) && !heard.playing(Look(sounding: true)))
    }

    @Test("with nothing sure before it, a press is judged by its menu's word changing or its sound")
    func pressJudgedByMenuWordOrSound() {
        let blind = Sign(before: Look(menuTitle: "Pause", sounding: true))
        #expect(blind.kind == nil && !blind.byLevel)
        #expect(blind.paused(Look(menuTitle: "Play", sounding: true)) && blind.paused(Look(menuTitle: "Pause", sounding: false)))
        #expect(!blind.paused(Look(menuTitle: "Pause", sounding: true)))
        #expect(blind.playing(Look(sounding: true)) && !blind.playing(Look(sounding: false)))
    }
}
