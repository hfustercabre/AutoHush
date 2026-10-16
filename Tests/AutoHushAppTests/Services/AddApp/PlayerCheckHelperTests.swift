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
    /// A stand-in for playercheck in `folder`: a shell script that runs `body`.
    private static func helper(_ body: String, in folder: URL) throws -> PlayerCheckHelper {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "playercheck")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return PlayerCheckHelper(url: url)
    }

    @Test("each question goes to the helper with AutoHush's folders, its answer read; a helper that can't start or takes too long tells nothing")
    func questions() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PlayerCheckHelperTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let folders = PlayerCheckHelper.folderArguments.joined(separator: " ")
        let helper = try Self.helper(#"""
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
    }

    @MainActor
    @Test("a check's lines come as the helper writes them, all before its end; it ends with the result it left, which goes, its log the newest; Stop ends it once it has put things back")
    func check() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PlayerCheckHelperTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = "check \(UUID().uuidString).log"
        defer { try? FileManager.default.removeItem(at: PlayerCheckHelper.logsFolder.appending(path: log)) }
        let found = CheckResult(ways: [CheckResult.WayResult(kind: .menu, mark: .works)], setup: nil)
        let finishing = try Self.helper(#"""
            for argument in "$@"; do
                case "$last" in --result) result=$argument ;; --logs) logs=$argument ;; esac
                last=$argument
            done
            echo "Press Test"
            echo "  checking $1, $last"
            cp "\#(folder.path)/found.json" "$result" && echo "$result"
            echo "its log" > "$logs/\#(log)"
            """#, in: folder)
        try JSONEncoder().encode(found).write(to: folder.appending(path: "found.json"))
        let player = URL(filePath: "/Applications/Player.app")
        let report = Report()
        let run = try finishing.check(player, taps: false) { report.lines.append($0) }
        #expect(await run.waitForEnd() == .finished(found))
        #expect(report.lines.count == 3 && report.lines.prefix(2) == ["Press Test", "  checking /Applications/Player.app, --no-taps"])
        #expect(report.lines.last.map { !FileManager.default.fileExists(atPath: $0) } == true) // read, then removed
        #expect(PlayerCheckHelper.newestLog?.lastPathComponent == log) // shown after a check that couldn't finish
        run.stop() // ended: nothing to stop
        #expect(await run.waitForEnd() == .finished(found))

        let waiting = try Self.helper(#"""
            trap 'kill $! 2>/dev/null; echo "  put back"; exit 143' TERM
            echo "Press Test"
            sleep 30 &
            wait
            """#, in: folder.appending(path: "waiting"))
        let stopped = Report()
        let stopping = try waiting.check(player, taps: true) { stopped.lines.append($0) }
        await TestWait.until { stopped.lines == ["Press Test"] }
        stopping.stop()
        #expect(await stopping.waitForEnd() == .stopped)
        #expect(stopped.lines == ["Press Test", "  put back"])
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
        let arguments = PlayerCheckHelper.checkArguments(app, result: result, taps: true)
        #expect(Array(arguments.prefix(5)) == ["/Applications/Deezer.app", "--block-input", "--partial", "--result", "/tmp/result.json"])
        #expect(arguments.contains("--logs") && arguments.contains("--caches") && !arguments.contains("--no-taps"))
        #expect(PlayerCheckHelper.checkArguments(app, result: result, taps: false).last == "--no-taps")
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
        #expect(PlayerCheckEnd.of(status: 1, stopped: false, result: nil) == .failed(1))
    }
}
