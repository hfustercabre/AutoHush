import Testing
@testable import CheckedPlayers

@Suite("CheckReportLine")
struct CheckReportLineTests {
    @Test("a window state's line reads back as it was written")
    func windowStates() {
        for (index, state) in CheckResult.WindowState.allCases.enumerated() {
            let line = CheckReportLine.windowState(index + 1, of: 7, state)
            let read = CheckReportLine.windowState(in: line)
            #expect(read?.index == index + 1 && read?.count == 7 && read?.state == state)
        }
        #expect(CheckReportLine.windowState(in: "  State of mind: fine") == nil)
    }

    @Test("a trial's label tells its way; a request its kind and minutes")
    func trialsAndRequests() {
        for way in CheckResult.WayKind.allCases {
            #expect(CheckReportLine.way(ofTrial: "  " + CheckReportLine.trial(way, detail: "a, b") + ": before, playing") == way)
        }
        #expect(CheckReportLine.trial(.page, learned: true) == "by its page's learned button")
        let line = CheckReportLine.waiting(.pause, "pause Jukebox yourself", minutes: 2)
        #expect(line == "  waiting: pause Jukebox yourself (up to 2 minutes)")
        #expect(CheckReportLine.request(in: line)?.request == .pause && CheckReportLine.request(in: line)?.minutes == 2)
        #expect(CheckReportLine.request(in: "  it plays") == nil)
        #expect(CheckReportLine.Heading(rawValue: "Press Test") == .pressTest)
    }
}
