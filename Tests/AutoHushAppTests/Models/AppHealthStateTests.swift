import AppKit
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

    @Test("a startup error sets the health: a denied permission is needed, a closed player degraded, one not responding or a failed command retried, others fail",
          arguments: [
            (MusicPlayerError.automationPermissionDenied as any Error, AppHealthState.needsPermission(.automation(player: "Jukebox"))),
            (MusicPlayerError.accessibilityPermissionDenied, .needsPermission(.accessibility(player: "Jukebox"))),
            (MusicPlayerError.playerNotRunning, .playerClosed("Jukebox isn’t running")),
            (MusicPlayerError.playerNotResponding, .retrying("Jukebox isn’t responding")),
            (MusicPlayerError.playerCommandFailed(.appleEventError(-50)), .retrying("Can’t control Jukebox right now")),
            (StubError.failed, .failed("Can’t control Jukebox right now")),
          ])
    func startupError(error: any Error, health expected: AppHealthState) {
        #expect(health(error) == expected)
    }

    @Test("each failure is said in words, with the log's English for a bug report; Now Playing hidden offers its settings")
    @MainActor func controlErrorWords() {
        let menu = ControlError(MusicPlayerError.playerCommandFailed(.menuItemNotFound), player: "TIDAL")
        #expect(menu.text == "AutoHush can’t find Play/Pause in TIDAL’s menus.")
        #expect(menu.detail == "Controlling the media player failed: its Play/Pause menu item wasn’t found.")
        #expect(ControlError(MusicPlayerError.playerCommandFailed(.appleEventError(-1708)), player: "Spotify").text
                == "Spotify answered with an error (-1708).")
        #expect(ControlError(MusicPlayerError.playerNotResponding, player: "VLC").text == "VLC isn’t responding.")
        #expect(ControlError(MusicPlayerError.automationPermissionDenied, player: "VLC").text == "AutoHush may no longer control VLC.")
        #expect(ControlError(StubError.failed, player: "Jukebox").text == "stub failed") // any other error: in its own words
        for failure: ControlFailure in [.stateUnknown, .nothingToPlay, .buttonDisabled, .pressFailed, .pressIgnored] {
            #expect(failure.text(player: "YT Music").contains("YT Music"))
        }
        // Only Now Playing hidden in the menu bar opens the pane where it's shown.
        #expect(ControlError(MusicPlayerError.playerCommandFailed(.nowPlayingHidden), player: "Qobuz").opensMenuBarSettings)
        #expect(!menu.opensMenuBarSettings)
        #expect(SystemSettingsPane.menuBar.url.absoluteString == "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")

        // Its alert: the button first (Return), OK after it (Escape), the pane opened by the first.
        var buttons: [(String, String)] = [], opened = 0
        InfoAlert.show("Couldn’t Pause Qobuz", "…", action: (ControlFailure.openMenuBarSettings, { opened += 1 })) { alert in
            buttons = alert.buttons.map { ($0.title, $0.keyEquivalent) }
            return .alertFirstButtonReturn
        }
        #expect(buttons.map(\.0) == [ControlFailure.openMenuBarSettings, "OK"] && buttons.map(\.1) == ["\r", "\u{1b}"] && opened == 1)
        // The pane as each macOS names it.
        if #available(macOS 26, *) {
            #expect(ControlFailure.openMenuBarSettings == "Open Menu Bar Settings…")
        } else {
            #expect(ControlFailure.openMenuBarSettings == "Open Control Center Settings…")
        }
    }

    @Test("while no player is chosen, the status asks for one: every Mac has some installed")
    func waitingForPlayer() {
        #expect(AppHealthState.waitingForPlayer == .needsPlayer("Choose a media player"))
    }

    @Test("a chosen player that isn't installed is degraded")
    func playerNotInstalled() {
        #expect(AppHealthState.playerNotInstalled("Jukebox") == .degraded("Jukebox isn’t installed"))
    }
}
