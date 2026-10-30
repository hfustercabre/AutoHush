import AppKit
import AutoHushKit
import CheckedPlayers
import os
import WebAppPlayers

/// The launch option an Electron app needs for its page to take presses
/// while its window is covered or on another desktop, AutoHush's
/// (`PlayerSetup.launchOption`). Without it, Chromium treats a page whose
/// window is fully out of view as hidden and ignores presses on it; with it,
/// an Electron player's worked covered, on another desktop and full screen
/// there. A CEF app took presses covered without it, so it's Electron's only.
enum LaunchOption {
    static let occludedWindows = PlayerSetup.launchOption

    /// The option the app needs, by the framework in its bundle, as AutoHush
    /// tells it (`CheckedAppTraits.needsLaunchOption`).
    static func needed(by url: URL) -> String? {
        PageAccess.interface(ofAppAt: url) == .electron ? occludedWindows : nil
    }

    /// Quits the app as a person would (never by force: it's given 15 s), then
    /// opens it again with `option`, in the background: an app that comes
    /// forward by itself once its window shows (some do) goes behind the
    /// app that was in front again. Says how it went (`tell`).
    @MainActor static func relaunch(_ app: NSRunningApplication?, url: URL, with option: String, tell: (String) -> Void) -> Bool {
        let name = AppName.of(appAt: url)
        let front = WindowStates.frontPID().flatMap { NSRunningApplication(processIdentifier: $0) }
        if let app {
            _ = app.terminate()
            Polling.wait(seconds: 15, every: 0.2, runLoop: true, until: { app.isTerminated })
            guard app.isTerminated else {
                tell("\(name) didn't quit within 15 s (it may be asking something): quit it yourself, then try again.")
                return false
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [option]
        configuration.activates = false
        // What `openApplication` answers, from the queue it answers on; read
        // under the lock also when the wait gives up as it answers.
        let opened = OSAllocatedUnfairLock<(app: NSRunningApplication?, error: any Error?)>(initialState: (nil, nil))
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { @Sendable app, error in // on another thread
            opened.withLock { $0 = (app, error) }
            done.signal()
        }
        let answered = done.wait(timeout: .now() + 30) == .success
        let (new, error) = opened.withLock { $0 }
        guard answered, let new else {
            tell("Couldn't open \(name) again: \(error?.localizedDescription ?? "macOS didn't answer").")
            return false
        }
        // It may come forward a few seconds after its window shows (one did
        // once its page loaded): watched for 12 s, sent back each time.
        if let front, front.processIdentifier != app?.processIdentifier {
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                if WindowStates.frontPID() == new.processIdentifier {
                    Thread.sleep(forTimeInterval: 0.3)
                    WindowStates.activate(front)
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        tell("\(app == nil ? "Opened" : "Relaunched") \(name) with \(option) (pid \(new.processIdentifier)).")
        return true
    }
}
