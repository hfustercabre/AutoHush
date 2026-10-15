import Foundation
import Testing
@testable import AutoHushApp
import CheckedPlayers

@Suite("CheckProgress")
struct CheckProgressTests {
    private func progress(_ lines: [String]) -> CheckProgress {
        var progress = CheckProgress()
        lines.forEach { progress.add($0, at: Date(timeIntervalSince1970: 100)) }
        return progress
    }

    @Test("the report's headings say which part the check is in")
    func stages() {
        #expect(progress(["Deezer 7.1 (com.deezer.deezer-desktop)", "Scripting Dictionary"]).stage == .reading)
        #expect(progress(["Permissions"]).stage == .permissions)
        #expect(progress(["Playing"]).stage == .playing)
        #expect(progress(["Window States"]).stage == .movingWindow)
        #expect(progress(["Page Buttons"]).stage == .readingPage)
        #expect(progress(["Press Test"]).stage == .testing)
        #expect(progress(["Press Test", "Ways to Control It"]).stage == .finishing)
    }

    @Test("the window state under test, then the way pressed and whether it pauses or plays again")
    func windowStates() {
        let moving = progress(["Press Test", "  State 3 of 7: on another desktop"])
        #expect(moving.windowStep == CheckProgress.WindowStep(index: 3, count: 7, state: .otherDesktop))
        #expect(moving.activity == .moving)
        let pausing = progress(["  State 3 of 7: on another desktop", "  by its menu: before, playing"])
        #expect(pausing.activity == .pausing(.menu))
        let again = progress(["  State 3 of 7: on another desktop", "  by its page's learned button: before, playing",
                              "    after the pause: paused → it paused"])
        #expect(again.activity == .playingAgain(.page))
        #expect(progress(["  State 4 of 7: covered on another desktop", "    not tested: no other desktop"]).activity == .untested)
    }

    @Test("a request lasts until it's answered or the report moves on, and lifts the block meanwhile")
    func requests() {
        let asked = progress(["Playing", "  your clicks, scrolling and keys are blocked until its window is put back",
                              "  waiting: start playing something in Deezer; the test goes on as soon as it plays (up to 2 minutes)"])
        #expect(asked.request == .play(minutes: 2))
        #expect(asked.requestSince == Date(timeIntervalSince1970: 100))
        #expect(asked.inputBlocked && !asked.blocksInput)
        #expect(progress(["  waiting: pause Deezer yourself (its own Pause, anywhere): … (up to 2 minutes)"]).request == .pause(minutes: 2))
        #expect(progress(["  waiting: start playing something in Deezer (up to 2 minutes)", "  it plays: testing"]).request == nil)
        #expect(progress(["  waiting: allow Accessibility for AutoHush (up to 2 minutes)", "Window States"]).request == nil)
    }

    @Test("the mouse and keyboard are blocked from the check's line until it frees them")
    func block() {
        let blocked = progress(["  your clicks, scrolling and keys are blocked until its window is put back"])
        #expect(blocked.blocksInput)
        #expect(!progress(["  your clicks, scrolling and keys are blocked until …", "  mouse and keyboard free again"]).blocksInput)
    }
}
