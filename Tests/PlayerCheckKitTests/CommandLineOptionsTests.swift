import Foundation
import Testing
@testable import PlayerCheckKit
import CheckedPlayers

@Suite("CommandLineOptions")
struct CommandLineOptionsTests {
    @Test("the app is the argument that's neither an option nor an option's value, wherever it comes")
    func app() {
        #expect(CommandLineOptions.app(in: ["/Applications/Player.app", "--block-input", "--partial", "--result", "/tmp/r.json",
                                            "--logs", "/tmp/logs", "--caches", "/tmp/caches", "--no-taps"]) == "/Applications/Player.app")
        #expect(CommandLineOptions.app(in: ["--logs", "/tmp/logs", "Player", "--via", "page", "--pause"]) == "Player")
        #expect(CommandLineOptions.app(in: [CommandLineOptions.developer, "/Applications/Player.app", "--block-input"]) == "/Applications/Player.app")
        #expect(CommandLineOptions.app(in: ["--read-only"]) == nil)
    }

    @Test("a query's operands leave out the folders AutoHush passes")
    func operands() {
        let reasons = ["/Applications/A.app", "/Applications/B.app", "--logs", "/Users/x/Library/Logs/AutoHush/Checks",
                       "--caches", "/Users/x/Library/Caches/com.autohush.AutoHush/PlayerCheck"]
        #expect(CommandLineOptions.operands(in: reasons) == ["/Applications/A.app", "/Applications/B.app"])
        #expect(CommandLineOptions.operands(in: ["24", "--logs", "/l", "--caches", "/c"]) == ["24"])
        #expect(CommandLineOptions.developer == "--developer")
        #expect(!CommandLineOptions.withValues.contains(CommandLineOptions.developer))
        #expect(CommandLineOptions.value(of: "--caches", in: reasons) == "/Users/x/Library/Caches/com.autohush.AutoHush/PlayerCheck")
        #expect(CommandLineOptions.value(of: "--result", in: reasons) == nil)
        #expect(CommandLineOptions.value(of: "--logs", in: ["--logs"]) == nil)
    }

    @Test("what AutoHush and the Player Check app run it with, the helper reads back: the app, each option, each value")
    func written() throws {
        let folders = CommandLineOptions.folders(logs: "/l", caches: "/c")
        let check = CommandLineOptions.check("/Applications/Player.app", partial: true, result: "/tmp/r.json", folders: folders, taps: false)
        #expect(check == ["/Applications/Player.app", "--block-input", "--partial", "--result", "/tmp/r.json", "--logs", "/l", "--caches", "/c", "--no-taps"])
        #expect(CommandLineOptions.app(in: check) == "/Applications/Player.app")
        #expect(CommandLineOptions.value(of: CommandLineOptions.result, in: check) == "/tmp/r.json")
        #expect(CommandLineOptions.value(of: CommandLineOptions.caches, in: check) == "/c")
        #expect([CommandLineOptions.blockInput, CommandLineOptions.partial, CommandLineOptions.noTaps].allSatisfy(check.contains))
        // The Player Check app's: blocking, with the developer's lines, nothing else.
        #expect(CommandLineOptions.check("/Applications/Player.app", developer: true) == ["/Applications/Player.app", "--block-input", "--developer"])

        let press = CommandLineOptions.press("/Applications/Player.app", .pause, via: .panel)
        #expect(press == ["/Applications/Player.app", "--pause", "--via", "panel"])
        #expect(CommandLineOptions.app(in: press) == "/Applications/Player.app")
        #expect(CommandLineOptions.value(of: CommandLineOptions.via, in: press).flatMap(CheckResult.WayKind.init(rawValue:)) == .panel)
        #expect(CommandLineOptions.Action.allCases.first { press.contains($0.option) } == .pause)
        #expect(CommandLineOptions.press("Player", .play, via: nil) == ["Player", "--play"])

        #expect(CommandLineOptions.nowPlayingList(hours: 24) == ["--now-playing-list", "24"])
        #expect(CommandLineOptions.nowPlayingList(hours: nil) == ["--now-playing-list"])
        let since = CommandLineOptions.nowPlayingList(since: Date(timeIntervalSince1970: 1_000))
        #expect(CommandLineOptions.value(of: CommandLineOptions.since, in: Array(since.dropFirst())).flatMap(Double.init) == 1_000)
        let reasons = CommandLineOptions.nowPlayingReasons(["/Applications/A.app", "/Applications/B.app"]) + folders
        #expect(reasons.first == CommandLineOptions.nowPlayingReasons)
        #expect(CommandLineOptions.operands(in: Array(reasons.dropFirst())) == ["/Applications/A.app", "/Applications/B.app"])
        for query in CommandLineOptions.AppQuery.allCases {
            let asked = query.arguments("/Applications/Player.app")
            #expect(CommandLineOptions.AppQuery(rawValue: asked[0]) == query && asked[1] == "/Applications/Player.app")
        }
    }

    @Test("its exit statuses: done, failed, a permission missing, and a stop by Stop or Ctrl-C")
    func exitStatuses() {
        #expect([CheckExitStatus.done, CheckExitStatus.failed, CheckExitStatus.permissionMissing] == [0, 1, 3])
        #expect(CheckExitStatus.stop == 143 && CheckExitStatus.stopped(by: SIGTERM) == 143 && CheckExitStatus.stopped(by: SIGINT) == 130)
        #expect(CheckExitStatus.isStop(143) && CheckExitStatus.isStop(130))
        #expect(!CheckExitStatus.isStop(CheckExitStatus.done) && !CheckExitStatus.isStop(CheckExitStatus.permissionMissing))
    }
}
