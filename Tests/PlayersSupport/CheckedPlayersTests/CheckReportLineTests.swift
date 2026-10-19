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

    @Test("a trial's label tells its way; each request the check makes, its kind and minutes")
    func trialsAndRequests() {
        for way in CheckResult.WayKind.allCases {
            #expect(CheckReportLine.way(ofTrial: "  " + CheckReportLine.trial(way, detail: "a, b") + ": before, playing") == way)
        }
        #expect(CheckReportLine.trial(.page, learned: true) == "by its page's learned button")
        let line = CheckReportLine.waiting("pause Jukebox yourself", minutes: 2)
        #expect(line == "  waiting: pause Jukebox yourself (up to 2 minutes)")
        let requests: [(line: String, request: CheckReportLine.Request)] = [
            (CheckReportLine.waitingToPlay("Jukebox", minutes: 2), .play), (CheckReportLine.waitingToPause("Jukebox", minutes: 2), .pause),
            (CheckReportLine.waitingForAccessibility("AutoHush", minutes: 2), .allowAccessibility),
        ]
        for (line, request) in requests {
            #expect(CheckReportLine.request(in: line)?.request == request && CheckReportLine.request(in: line)?.minutes == 2, "\(line)")
        }
        #expect(CheckReportLine.request(in: "  it plays") == nil)
        #expect(CheckReportLine.Heading(rawValue: "Press Test") == .pressTest)
    }

    @Test("a request's own words read back without its prefix")
    func requestText() {
        #expect(CheckReportLine.requestText(in: CheckReportLine.waitingToPlay("Jukebox", minutes: 2))?.hasPrefix("start playing something in Jukebox") == true)
        #expect(CheckReportLine.requestText(in: "  it plays") == nil)
    }

    @Test("a permission's line reads back as missing when it isn't allowed or answered, with its name; Accessibility's answers its request")
    func permissions() {
        let permissions: [CheckReportLine.Permission] = [.accessibility, .audioRecording, .automation(app: "Jukebox")]
        for permission in permissions {
            #expect(CheckReportLine.Permission(name: permission.name) == permission)
            #expect(CheckReportLine.missingPermission(in: CheckReportLine.permission(permission, .notAllowed)) == permission)
            #expect(CheckReportLine.missingPermission(in: CheckReportLine.permission(permission, .notAnswered)) == permission)
            #expect(CheckReportLine.missingPermission(in: CheckReportLine.permission(permission, .allowed)) == nil)
            #expect(CheckReportLine.missingPermission(in: CheckReportLine.permission(permission, "not used (AntiDot mode)")) == nil)
        }
        #expect(CheckReportLine.permission(.automation(app: "Jukebox"), .notAllowed) == "  Automation for Jukebox: not allowed")
        #expect(CheckReportLine.Permission(name: "System Audio Recording") == .audioRecording) // older checks' name
        #expect(CheckReportLine.answers.contains { CheckReportLine.permission(.accessibility, .allowed).hasPrefix($0) })
        let notChecked = CheckReportLine.notChecked("AutoHush needs Accessibility.")
        #expect(CheckReportLine.notChecked(in: notChecked) == "AutoHush needs Accessibility.")
        #expect(CheckReportLine.notChecked(in: "  Accessibility: allowed") == nil)
    }

    @Test("a way's line and its window states' lines read back: its mark, its way, title and detail; failed or not tested, and why")
    func ways() {
        for mark in CheckReportLine.WayMark.allCases {
            for way in CheckResult.WayKind.allCases {
                let line = CheckReportLine.way(mark, CheckReportLine.wayTitle(way) + " “Controls”: pressing it paused and played it")
                let read = CheckReportLine.way(in: line)
                #expect(read?.mark == mark && read?.way == way && read?.title == CheckReportLine.wayTitle(way) + " “Controls”")
                #expect(read?.detail == "pressing it paused and played it")
                #expect(CheckReportLine.wayState(in: line) == nil)
            }
        }
        let failed = CheckReportLine.wayState(.none, CheckResult.WindowState.covered.title, "pressing it changed nothing")
        #expect(failed == "      ✗ covered: pressing it changed nothing")
        let read = CheckReportLine.wayState(in: failed)
        #expect(read?.failed == true && read?.state == "covered" && read?.why == "pressing it changed nothing")
        let untested = CheckReportLine.wayState(.notChecked, "window states", "not tested (no window)")
        #expect(CheckReportLine.wayState(in: untested)?.failed == false && CheckReportLine.way(in: untested) == nil)
        #expect(CheckReportLine.way(in: "  State 1 of 7: visible") == nil)
    }
}
