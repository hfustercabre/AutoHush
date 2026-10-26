import Foundation
import CheckedPlayers

/// The ways to pause and play an app added with Add an App, as its check
/// names them: the Add an App window, the check's panel, and Settings →
/// Diagnostics under "Controlled by".
enum WayText {
    static func title(_ way: CheckResult.WayKind) -> String {
        switch way {
        case .script: String(localized: "AppleScript", comment: "A way to pause and play an app added with Add an App: its AppleScript commands (the Add an App window, the check's panel, Settings → Diagnostics under “Controlled by”)")
        case .menu: String(localized: "Its playback menu", comment: "A way to pause and play an app added with Add an App: the Play/Pause item of its menu bar's playback menu (the Add an App window, Settings → Diagnostics under “Controlled by”)")
        case .page: String(localized: "Its page’s Play/Pause", comment: "A way to pause and play an app added with Add an App: the Play/Pause button of the page it shows (the Add an App window, Settings → Diagnostics under “Controlled by”)")
        case .panel: String(localized: "The menu bar’s Now Playing panel", comment: "A way to pause and play an app added with Add an App: its row in macOS's Now Playing panel (the Add an App window, Settings → Diagnostics under “Controlled by”)")
        }
    }
}
