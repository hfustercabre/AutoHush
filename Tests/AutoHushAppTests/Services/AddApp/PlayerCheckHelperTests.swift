import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport
import CheckedPlayers

/// A check's lines, as they come.
@MainActor
private final class Report {
    var lines: [String] = []
}

@Suite("PlayerCheckHelper")
struct PlayerCheckHelperTests {
    @Test("each question goes to the helper with its folders, its answer read; a helper that can't start or takes too long tells nothing")
    func questions() async throws {
        let scratch = TemporaryFolder("PlayerCheckHelperTests", create: false)
        let folder = scratch.url
        let folders = "--logs \(folder.path)/Logs --caches \(folder.path)/Caches"
        let helper = try PlayerCheckHelper.standIn(#"""
            case " $* " in *" \#(folders) "*) ;; *) exit 2 ;; esac
            case "$1" in
            --now-playing-list) [ "$2" = 24 ] && printf 'com.example.player\t412\tPlaying\t1\tPlayer\ncom.example.paused\t300\tPaused\t0\tPaused\n#active\t412\n' ;;
            --now-playing-reasons) printf '%s\tits bundle reports\t\t\n%s\t\t\t\n' "$2" "$3" ;;
            --launch-option) [ "$2" = /Applications/Player.app ] && printf '%s\tno\n' --disable-backgrounding-occluded-windows ;;
            --relaunch) [ "$2" = /Applications/Player.app ] ;;
            *) exec sleep 30 ;;
            esac
            """#, in: folder)
        let player = URL(filePath: "/Applications/Player.app")
        #expect(await helper.nowPlaying() == ["com.example.player": true, "com.example.paused": false])
        #expect(await helper.canPlay([player, URL(filePath: "/Applications/Notes.app")]) == [player.path])
        #expect(await helper.canPlay([]).isEmpty) // nothing to ask
        #expect(await helper.runsWithLaunchOption(player) == false)
        #expect(await helper.reopenWithLaunchOption(player))
        #expect(await helper.run(["--slow"], timeout: 0.2).status == -1) // given up

        let missing = PlayerCheckHelper(url: folder.appending(path: "absent"))
        #expect(await missing.run(["--now-playing-list"]).status == -1)
        #expect(await missing.nowPlaying().isEmpty)
        #expect(await missing.canPlay([player]).isEmpty)
        #expect(await missing.runsWithLaunchOption(player) == nil)
        #expect(await !missing.reopenWithLaunchOption(player))
        withExtendedLifetime(scratch) {}
    }

    /// The log the stand-in helper of `finishedCheck` writes.
    private static let checkLog = "2026-10-19 10.00.00.000 Player check.log"

    /// A check of Player by a stand-in helper, in a scratch folder (the
    /// caller keeps it to its end), that writes three lines, the last the
    /// result it leaves (`found`), and its log; the check started, not
    /// waited for.
    @MainActor
    private func finishedCheck() throws
        -> (scratch: TemporaryFolder, found: CheckResult, helper: PlayerCheckHelper, run: PlayerCheckRun, report: Report) {
        let scratch = TemporaryFolder("PlayerCheckHelperTests", create: false)
        let folder = scratch.url
        let found = CheckResult(ways: [CheckResult.WayResult(kind: .menu, mark: .works)], setup: nil)
        let finishing = try PlayerCheckHelper.standIn(#"""
            for argument in "$@"; do
                case "$last" in --result) result=$argument ;; --logs) logs=$argument ;; esac
                last=$argument
            done
            echo "Press Test"
            echo "  checking $1, $last"
            cp "\#(folder.path)/found.json" "$result" && echo "$result"
            echo "its log" > "$logs/\#(Self.checkLog)"
            """#, in: folder)
        try JSONEncoder().encode(found).write(to: folder.appending(path: "found.json"))
        let report = Report()
        let run = try finishing.check(URL(filePath: "/Applications/Player.app"), taps: false) { report.lines.append($0) }
        return (scratch, found, finishing, run, report)
    }

    @MainActor
    @Test("a check's lines come as the helper writes them, all before its end")
    func check() async throws {
        let bench = try finishedCheck()
        _ = await bench.run.waitForEnd()
        #expect(bench.report.lines.count == 3 && bench.report.lines.prefix(2) == ["Press Test", "  checking /Applications/Player.app, --no-taps"])
        withExtendedLifetime(bench.scratch) {}
    }

    @MainActor
    @Test("a check ends with the result the helper left, which goes once read")
    func checkResult() async throws {
        let bench = try finishedCheck()
        #expect(await bench.run.waitForEnd() == .finished(bench.found))
        #expect(bench.report.lines.last.map { !FileManager.default.fileExists(atPath: $0) } == true) // read, then removed
        withExtendedLifetime(bench.scratch) {}
    }

    @MainActor
    @Test("a check's log is the newest the helper wrote")
    func checkLogIsNewest() async throws {
        let bench = try finishedCheck()
        _ = await bench.run.waitForEnd()
        #expect(PlayerCheckHelper.newestLog(in: bench.helper.logs)?.lastPathComponent == Self.checkLog) // shown after a check that couldn't finish
        withExtendedLifetime(bench.scratch) {}
    }

    @MainActor
    @Test("Stop after a check ended changes nothing")
    func stopAfterTheEnd() async throws {
        let bench = try finishedCheck()
        _ = await bench.run.waitForEnd()
        bench.run.stop() // ended: nothing to stop
        #expect(await bench.run.waitForEnd() == .finished(bench.found))
        withExtendedLifetime(bench.scratch) {}
    }

    @MainActor
    @Test("Stop ends a check once the helper has put things back")
    func stopEndsTheCheck() async throws {
        let scratch = TemporaryFolder("PlayerCheckHelperTests", create: false)
        let waiting = try PlayerCheckHelper.standIn(#"""
            trap 'kill $! 2>/dev/null; echo "  put back"; exit 143' TERM
            echo "Press Test"
            sleep 30 &
            wait
            """#, in: scratch.appending(path: "waiting"))
        let stopped = Report()
        let stopping = try waiting.check(URL(filePath: "/Applications/Player.app"), taps: true) { stopped.lines.append($0) }
        await TestWait.until { stopped.lines == ["Press Test"] }
        stopping.stop()
        #expect(await stopping.waitForEnd() == .stopped)
        #expect(stopped.lines == ["Press Test", "  put back"])
        withExtendedLifetime(scratch) {}
    }

    @Test("the helper is found inside AutoHush.app, or beside the executable of a build run from .build, where it can run")
    func bundled() throws {
        let scratch = TemporaryFolder("PlayerCheckHelperTests", create: false)
        let app = scratch.appending(path: "AutoHush.app")
        let executable = app.appending(path: "Contents/MacOS/AutoHush")
        #expect(PlayerCheckHelper.bundled(in: app, beside: executable) == nil)

        let inside = try PlayerCheckHelper.standIn("exit 0", in: app.appending(path: "Contents/Helpers"))
        #expect(PlayerCheckHelper.bundled(in: app, beside: executable)?.url.path == inside.url.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: inside.url.path) // can't run
        #expect(PlayerCheckHelper.bundled(in: app, beside: executable) == nil)
        let beside = try PlayerCheckHelper.standIn("exit 0", in: executable.deletingLastPathComponent())
        #expect(PlayerCheckHelper.bundled(in: app, beside: executable)?.url.path == beside.url.path)
        withExtendedLifetime(scratch) {}
    }

    @Test("Show Log opens the newest run's log the helper wrote, never another file there (Finder's .DS_Store, once the folder was opened)")
    func newestLog() throws {
        let scratch = TemporaryFolder("PlayerCheckHelperTests")
        let folder = scratch.url
        #expect(PlayerCheckHelper.newestLog(in: folder) == nil)
        let names = ["2026-10-19 09.00.00.000 Player check.log", "2026-10-19 10.00.00.000 Player check.log", ".DS_Store", "notes.log", "Open Me.command"]
        for (index, name) in names.enumerated() {
            let url = folder.appending(path: name)
            #expect(FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8)))
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: Double(index - 10) * 60)], ofItemAtPath: url.path)
        }
        #expect(PlayerCheckHelper.newestLog(in: folder)?.lastPathComponent == names[1])
        withExtendedLifetime(scratch) {}
    }

    @Test("the Now Playing list: each app's bundle ID and whether it plays, apart from those removed and the active line")
    func nowPlayingList() {
        let output = """
        com.deezer.deezer-desktop\t412\tPlaying\t1\tDeezer
        com.apple.TV\t300\tPaused\t0\tTV
        com.example.gone\t12\tRemoved\t0\tGone
        \t13\tPlaying\t0\tNameless
        #active\t412
        """
        #expect(PlayerCheckHelper.nowPlaying(fromList: output) == ["com.deezer.deezer-desktop": true, "com.apple.TV": false])
    }

    @Test("the apps that can play are those with a reason")
    func canPlay() {
        let output = "/Applications/Deezer.app\tits bundle reports\telectron\tAXManualAccessibility\n/Applications/Notes.app\t\t\t\n"
        #expect(PlayerCheckHelper.canPlay(fromReasons: output) == ["/Applications/Deezer.app"])
    }

    @Test("the launch option's answer: yes, no, or nothing to tell")
    func launchOption() {
        #expect(PlayerCheckHelper.runsWithLaunchOption(fromAnswer: "--disable-backgrounding-occluded-windows\tyes\n") == true)
        #expect(PlayerCheckHelper.runsWithLaunchOption(fromAnswer: "--disable-backgrounding-occluded-windows\tno") == false)
        #expect(PlayerCheckHelper.runsWithLaunchOption(fromAnswer: "\tno") == nil)
        #expect(PlayerCheckHelper.runsWithLaunchOption(fromAnswer: "") == nil)
    }

    @Test("a check's arguments: the app, the block, partial, its result, AutoHush's folders, and no taps in AntiDot mode")
    func checkArguments() {
        let app = URL(filePath: "/Applications/Deezer.app")
        let result = URL(filePath: "/tmp/result.json")
        let helper = PlayerCheckHelper(url: URL(filePath: "/usr/bin/true"))
        let arguments = helper.checkArguments(app, result: result, taps: true)
        #expect(Array(arguments.prefix(5)) == ["/Applications/Deezer.app", "--block-input", "--partial", "--result", "/tmp/result.json"])
        #expect(Array(arguments.dropFirst(5)) == ["--logs", PlayerCheckHelper.logsFolder.path, "--caches", PlayerCheckHelper.cachesFolder.path])
        #expect(helper.checkArguments(app, result: result, taps: false).last == "--no-taps")
    }

    @Test("how the helper's exit ends a check")
    func ends() throws {
        let result = CheckResult(ways: [CheckResult.WayResult(kind: .menu, mark: .notThere)], setup: nil)
        let data = try JSONEncoder().encode(result)
        #expect(PlayerCheckEnd.of(status: 0, stopped: false, result: data) == .finished(result))
        #expect(PlayerCheckEnd.of(status: 0, stopped: false, result: nil) == .finished(nil))
        #expect(PlayerCheckEnd.of(status: 0, stopped: false, result: Data("{".utf8)) == .finished(nil))
        #expect(PlayerCheckEnd.of(status: 3, stopped: false, result: nil) == .permissionMissing)
        #expect(PlayerCheckEnd.of(status: 143, stopped: false, result: nil) == .stopped)
        #expect(PlayerCheckEnd.of(status: 130, stopped: false, result: nil) == .stopped)
        #expect(PlayerCheckEnd.of(status: 1, stopped: true, result: nil) == .stopped)
        // Ended by a signal: its number isn't an exit status.
        #expect(PlayerCheckEnd.of(status: SIGQUIT, bySignal: true, stopped: false, result: nil) == .failed(128 + SIGQUIT))
        #expect(PlayerCheckEnd.of(status: SIGTERM, bySignal: true, stopped: false, result: nil) == .stopped)
        #expect(PlayerCheckEnd.of(status: 1, stopped: false, result: nil) == .failed(1))
    }
}
