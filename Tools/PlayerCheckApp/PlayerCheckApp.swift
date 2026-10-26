// Player Check: a window over Sources/PlayerCheck. It lists the apps in the
// Applications folders (/Applications, ~/Applications, /System/Applications,
// with their subfolders: Safari web apps included) that can be in macOS's
// Now Playing list, those macOS lists now first (playercheck's
// --now-playing-list, from macOS's log). Once an app is chosen and the check
// confirmed, it runs playercheck on it (opening it first when needed) and
// shows the ways it could be controlled (each tested with the app's window
// in every state a player's can be in: ✓ all, ⚠ some, ✗ none), the verdict
// (with its developer lines: playercheck --developer) and the full report;
// checks are kept between launches. An app whose check
// found a way that works gets Play and Pause buttons, by the first way that
// worked with its window as it is when pressed (playercheck --window-state),
// and each way found gets its own (playercheck --play/--pause --via …). An
// Electron app running without the launch option its page needs out of view
// gets a Relaunch button (playercheck --launch-option, --relaunch). While a
// check runs, a small panel at the screen's bottom right shows how far it
// has got, with Stop, on every desktop (the check's panel, as AutoHush's Add
// an App… shows it). It runs playercheck as AutoHush does, through the same
// interface (PlayerCheckKit's command line, exit statuses and answers,
// CheckedPlayers' report lines and progress) and AutoHushKit's `ToolRun`.
// Build: sh Tools/PlayerCheckApp/build.sh [folder] (the package's PlayerCheckApp
// product, in an app with playercheck inside it).
import AppKit
import SwiftUI

/// Holds the checker for the app's whole life, not the window's: closing
/// the window quits the app, and its view may be gone by then, so the check
/// or Play/Pause still running is stopped here.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let checker = Checker()
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { checker.stopAll() }
}

@main
struct PlayerCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Player Check", id: "main") {
            ContentView(checker: delegate.checker)
                .neverFullScreen()
        }
        .defaultSize(width: 980, height: 680)
    }
}

private extension View {
    /// Never full screen, from macOS 15; an AppKit collection behavior set
    /// on the window didn't hold, so before it the green button still can.
    @ViewBuilder func neverFullScreen() -> some View {
        if #available(macOS 15, *) { windowFullScreenBehavior(.disabled) } else { self }
    }
}
