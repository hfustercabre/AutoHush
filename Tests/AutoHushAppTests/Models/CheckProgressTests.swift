import Foundation
import Testing
@testable import AutoHushApp
import CheckedPlayers

@Suite("CheckProgress")
struct CheckProgressTests {
    private typealias Line = CheckReportLine

    private func progress(_ lines: [String]) -> CheckProgress {
        var progress = CheckProgress()
        lines.forEach { progress.add($0, at: Date(timeIntervalSince1970: 100)) }
        return progress
    }

    @Test("the report's headings say which part the check is in")
    func stages() {
        #expect(progress(["Deezer 7.1 (com.deezer.deezer-desktop)", Line.Heading.scripting.rawValue]).stage == .reading)
        #expect(progress([Line.Heading.permissions.rawValue]).stage == .permissions)
        #expect(progress([Line.Heading.playing.rawValue]).stage == .playing)
        #expect(progress([Line.Heading.windowStates.rawValue]).stage == .movingWindow)
        #expect(progress([Line.Heading.page.rawValue]).stage == .readingPage)
        #expect(progress([Line.Heading.pressTest.rawValue]).stage == .testing)
        #expect(progress([Line.Heading.pressTest.rawValue, Line.Heading.ways.rawValue]).stage == .finishing)
        // As playercheck writes them.
        #expect(progress(["Press Test"]).stage == .testing)
    }

    @Test("the window state under test, then the way pressed and whether it pauses or plays again")
    func windowStates() {
        let moving = progress([Line.Heading.pressTest.rawValue, Line.windowState(3, of: 7, .otherDesktop)])
        #expect(moving.windowStep == CheckProgress.WindowStep(index: 3, count: 7, state: .otherDesktop))
        #expect(moving.activity == .moving)
        #expect(Line.windowState(3, of: 7, .otherDesktop) == "  State 3 of 7: on another desktop")
        let pausing = progress([Line.windowState(3, of: 7, .otherDesktop), "  \(Line.trial(.menu)): before, playing"])
        #expect(pausing.activity == .pausing(.menu))
        let again = progress([Line.windowState(3, of: 7, .otherDesktop), "  \(Line.trial(.page, learned: true)): before, playing",
                              "\(Line.afterPause): paused → it paused"])
        #expect(again.activity == .playingAgain(.page))
        #expect(progress(["  \(Line.trial(.script, detail: "playpause, playpause")): before, state playing"]).activity == .pausing(.script))
        #expect(progress(["  \(Line.trial(.panel)): before, sound on"]).activity == .pausing(.panel))
        #expect(progress([Line.windowState(4, of: 7, .otherDesktopCovered), "\(Line.notTested): no other desktop"]).activity == .untested)
    }

    @Test("a request lasts until it's answered or the report moves on, and lifts the block meanwhile")
    func requests() {
        let asked = progress([Line.Heading.playing.rawValue, Line.blocked + " until its window is put back",
                              Line.waiting(.play, "start playing something in Deezer; the test goes on as soon as it plays", minutes: 2)])
        #expect(asked.request == .play(minutes: 2))
        #expect(asked.requestSince == Date(timeIntervalSince1970: 100))
        #expect(asked.inputBlocked && !asked.blocksInput)
        #expect(progress([Line.waiting(.pause, "pause Deezer yourself (its own Pause, anywhere): …", minutes: 2)]).request == .pause(minutes: 2))
        #expect(progress([Line.waiting(.play, "start playing something in Deezer", minutes: 2), "  it plays: testing"]).request == nil)
        #expect(progress([Line.waiting(.allowAccessibility, "allow Accessibility for AutoHush", minutes: 3),
                          Line.Heading.windowStates.rawValue]).request == nil)
        #expect(progress([Line.waiting(.allowAccessibility, "allow Accessibility for AutoHush", minutes: 3)]).request
            == .allowAccessibility(minutes: 3))
    }

    @Test("the mouse and keyboard are blocked from the check's line until it frees them")
    func block() {
        let blocked = progress([Line.blocked + " until its window is put back"])
        #expect(blocked.blocksInput)
        #expect(!progress([Line.blocked + " until …", Line.free]).blocksInput)
        #expect(!progress([Line.blocked + " until …", Line.free + ": the check wrote nothing for 60 s"]).blocksInput)
    }
}
