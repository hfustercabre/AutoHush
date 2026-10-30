import AppKit
import AutoHushKit

/// An Electron app whose page is one of its ways must be opened with
/// `PlayerSetup.launchOption` for its page to take presses while its window
/// is covered or on another desktop (Chromium treats it as hidden then).
extension CheckedPlayer {
    /// Its page is a way, and it runs without the option.
    package func needsReopen() async -> Bool {
        guard setup.needsLaunchOption, setup.ways.contains(where: { if case .page = $0 { true } else { false } }),
              let pid = processIdentifier() else { return false }
        return !processArguments(pid).contains(PlayerSetup.launchOption)
    }

    /// Quits it as a person would (given 15 s, never by force), then opens it
    /// again with the option, in the background.
    package func reopen() async -> Bool {
        if let app = NSRunningApplication.running(bundleID) {
            _ = app.terminate()
            for _ in 0..<60 where !app.isTerminated { try? await Task.sleep(for: .milliseconds(250)) }
            guard app.isTerminated else { return false }
        }
        // Where it is now: it may have been moved since its check.
        return await openWithLaunchOption(installedURL ?? setup.appURL)
    }

    /// Opens the app at `url` with `PlayerSetup.launchOption`, in the background.
    static func openWithLaunchOption(_ url: URL) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [PlayerSetup.launchOption]
        configuration.activates = false
        return (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil
    }
}
