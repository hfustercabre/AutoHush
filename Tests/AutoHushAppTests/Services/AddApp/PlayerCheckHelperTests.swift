import Foundation
import Testing
@testable import AutoHushApp
import CheckedPlayers

@Suite("PlayerCheckHelper")
struct PlayerCheckHelperTests {
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
