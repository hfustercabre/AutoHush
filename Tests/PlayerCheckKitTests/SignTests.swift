import AutoHushKit
import Testing
@testable import PlayerCheckKit

@Suite("Sign")
struct SignTests {
    @Test("a look's surest sign, in AutoHush's order: the scripted state, the page's current word, the menu, Now Playing's report, the level, the keep-awake assertion")
    func surestSign() {
        #expect(SignKind.allCases == [.script, .page, .menu, .report, .level, .awake])
        var look = Look(menuTitle: "Pause", menuState: .playing, state: .paused, reported: "Playing", pageToggle: "Play",
                        pageSays: .paused, sounding: true, audible: true, awake: true)
        #expect(look.surest == .script && look.says(.script) == .paused && look.says(.report) == .playing)
        look.state = nil
        #expect(look.surest == .page && look.says(.page) == .paused)
        look.pageSays = nil
        #expect(look.surest == .menu) // before the report, as AutoHush reads an added app's
        look.menuState = nil
        #expect(look.surest == .report)
        look.reported = nil
        #expect(look.surest == .level)
        look.audible = nil
        #expect(look.surest == .awake)
        look.awake = nil
        #expect(look.surest == nil)
        // A page's word out of sight, or one it doesn't know, says nothing.
        var page = Look(pageToggle: "Pausa", pageSays: .playing, pageCurrent: false, sounding: true, awake: false)
        #expect(page.says(.page) == nil && page.surest == .awake)
        page.pageCurrent = true
        #expect(page.surest == .page)
        page.pageSays = nil
        #expect(page.says(.page) == nil)
    }

    @Test("a look is stopped as its scripted state says, else the menu, else Now Playing's report")
    func stopped() {
        #expect(Look(menuState: .stopped, sounding: false).stopped)
        #expect(Look(menuState: .stopped, reported: "Paused", sounding: false).stopped) // the menu is surer
        #expect(!Look(menuState: .paused, reported: "Stopped", sounding: false).stopped)
        #expect(!Look(menuState: .stopped, state: .paused, sounding: false).stopped) // the scripted state, surer still
        #expect(Look(reported: "Stopped", sounding: false).stopped && !Look(sounding: false, audible: false).stopped)
    }

    @Test("a press is judged by the surest sign before it")
    func pressJudgedBySurestSign() {
        let heard = Sign(before: Look(sounding: true, audible: true))
        #expect(heard.kind == .level && heard.byLevel)
        #expect(heard.paused(Look(sounding: true, audible: false)) && !heard.paused(Look(sounding: false))) // unmeasured: no answer
        #expect(heard.playing(Look(sounding: true, audible: true)) && !heard.playing(Look(sounding: true)))
        // Its menu before its level, as AutoHush reads an added app's.
        let menu = Sign(before: Look(menuTitle: "Pause", menuState: .playing, sounding: true, audible: true))
        #expect(menu.kind == .menu && !menu.byLevel)
        #expect(menu.paused(Look(menuTitle: "Play", menuState: .paused, sounding: true, audible: true)))
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
