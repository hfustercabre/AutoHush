import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("AppHealthState")
struct AppHealthStateTests {
    private func health(_ error: any Error) -> AppHealthState {
        AppHealthState(startupError: error, playerName: "Jukebox")
    }

    @Test("denied Automation needs permission")
    func automationDenied() {
        #expect(health(MusicPlayerError.automationPermissionDenied) == .needsPermission(.automation(player: "Jukebox")))
        #expect(health(MusicPlayerError.accessibilityPermissionDenied) == .needsPermission(.accessibility(player: "Jukebox")))
    }

    @Test("a player that isn't running is degraded")
    func playerNotRunning() {
        #expect(health(MusicPlayerError.playerNotRunning) == .degraded("Jukebox is not running"))
    }

    @Test("an unresponsive player is retried")
    func playerNotResponding() {
        #expect(health(MusicPlayerError.playerNotResponding) == .retrying("Jukebox is not responding"))
    }

    @Test("a failed player command is retried; the line says AutoHush can't control it, the menu tells why")
    func commandFailed() {
        #expect(health(MusicPlayerError.playerCommandFailed(.appleEventError(-50, message: nil)))
            == .retrying("Can't control Jukebox right now"))
    }

    @Test("each failure is said in words, with the log's English for a bug report")
    func controlErrorWords() {
        let menu = ControlError(MusicPlayerError.playerCommandFailed(.menuItemNotFound), player: "TIDAL")
        #expect(menu.text == "AutoHush can't find Play/Pause in TIDAL's menus.")
        #expect(menu.detail == "Controlling the media player failed: its Play/Pause menu item wasn't found.")
        #expect(ControlError(MusicPlayerError.playerCommandFailed(.appleEventError(-1708, message: "Not understood")), player: "Spotify").text
                == "Spotify answered with an error (-1708).")
        #expect(ControlError(MusicPlayerError.playerNotResponding, player: "VLC").text == "VLC isn't responding.")
        #expect(ControlError(MusicPlayerError.automationPermissionDenied, player: "VLC").text == "AutoHush may no longer control VLC.")
        for failure: ControlFailure in [.stateUnknown, .nothingToPlay, .buttonDisabled, .pressFailed, .pressIgnored] {
            #expect(failure.text(player: "YT Music").contains("YT Music"))
        }
    }

    @Test("messages name the player")
    func namesThePlayer() {
        #expect(AppHealthState(startupError: MusicPlayerError.playerNotRunning, playerName: "Music")
            == .degraded("Music is not running"))
    }

    @Test("while no player is chosen, the status asks for one, or says none is installed")
    func waitingForPlayer() {
        let installed = PlayerOption(bundleID: "com.example.a", name: "A", appURL: URL(fileURLWithPath: "/Applications/A.app"))
        let missing = PlayerOption(bundleID: "com.example.b", name: "B", appURL: nil)
        #expect(AppHealthState.waitingForPlayer(among: [missing, installed]) == .needsPlayer("Choose a media player"))
        #expect(AppHealthState.waitingForPlayer(among: [missing])
            == .needsPlayer("No supported media player is installed"))
    }

    @Test("a chosen player that isn't installed is degraded")
    func playerNotInstalled() {
        #expect(AppHealthState.playerNotInstalled("Jukebox") == .degraded("Jukebox is not installed"))
    }

    @Test("any other error fails; the menu tells why, in the error's own words")
    func otherError() {
        #expect(health(StubError.failed) == .failed("Can't control Jukebox right now"))
        #expect(ControlError(StubError.failed, player: "Jukebox").text == "stub failed")
    }
}
