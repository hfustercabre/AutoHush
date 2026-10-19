import Foundation
import Testing
@testable import PlayerCheckKit
import CheckedPlayers

@Suite("RunLogName")
struct RunLogNameTests {
    @Test("a run's log is named by its time, the app and what the run did", arguments: [
        "2026-10-18 09.41.07.250 Jukebox pause via panel.log", "2026-10-18 09.41.07.250 Some Player relaunch.log",
        "2026-10-18 09.41.07.250 Jukebox play.log",
    ])
    func runLogName(_ name: String) {
        #expect(RunLogName.isRunLog(name))
    }

    @Test("a name without its time, its app or what the run did, or not a log, is no run's log", arguments: [
        "2026-10-18 09.41.07.250 check.log", "2026-10-18 Jukebox check.log", "2026-10-18 09.41.07.250 Jukebox check.txt",
        "2026-13-18 09.41.07.250 Jukebox check.log", "2026-10-18 09.41.07.250 Jukebox listening.log", ".DS_Store",
    ])
    func notARunLogName(_ name: String) {
        #expect(!RunLogName.isRunLog(name))
    }

    @Test("each run's name is one it knows again: a check, one read only, a press by any way or none, a relaunch; / and : written -")
    func names() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-18T09:41:07Z"))
        let doings = [RunLogName.doing(nil, via: nil, readOnly: false), RunLogName.doing(nil, via: nil, readOnly: true), RunLogName.relaunch]
            + CommandLineOptions.Action.allCases.flatMap { action in
                [RunLogName.doing(action, via: nil, readOnly: false)] + CheckResult.WayKind.allCases.map { RunLogName.doing(action, via: $0, readOnly: false) }
            }
        #expect(doings.prefix(3) == ["check", "read-only", "relaunch"] && doings.contains("pause via panel"))
        for doing in doings {
            #expect(RunLogName.isRunLog(RunLogName.name(at: date, app: "AC/DC: Live", doing: doing)))
        }
        #expect(RunLogName.name(at: date, app: "AC/DC: Live", doing: "check").hasSuffix(" AC-DC- Live check.log"))
    }
}
