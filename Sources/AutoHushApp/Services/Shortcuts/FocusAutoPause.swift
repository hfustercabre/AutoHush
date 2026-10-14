import Foundation
import AutoHushKit

/// Follows a Focus with AutoHush's filter: when it turns on, notes how
/// Auto-Pause stands and applies the filter's choice; when it ends, puts
/// the noted state back, unless the user changed Auto-Pause meanwhile. The
/// note is saved in `Preferences`, so a quit or a restart during the Focus
/// still ends with the state restored.
@MainActor
final class FocusAutoPause {
    private let control: any AutoPauseControlling
    private let preferences: Preferences

    init(control: any AutoPauseControlling, preferences: Preferences) {
        self.control = control
        self.preferences = preferences
    }

    /// A Focus's choice (true = Auto-Pause on), or nil when no Focus with
    /// the filter is on.
    func follow(_ choice: Bool?, now: Date = Date()) {
        if let choice {
            // A second Focus keeps the first one's note: the state to come
            // back to is the one before it.
            let noted = preferences.focusAutoPause?.noted ?? control.autoPauseSetting
            preferences.focusAutoPause = FocusAutoPauseNote(noted: noted, applied: choice)
            control.setAutoPause(choice)
        } else if let note = preferences.focusAutoPause {
            // What the user set during the Focus (menu, Settings, an action) stands.
            if control.autoPauseSetting == AutoPauseSetting(isEnabled: note.applied, snoozedUntil: nil) {
                control.restoreAutoPause(note.noted, now: now)
            }
            preferences.focusAutoPause = nil
        }
    }

    /// The launch call, with the filter macOS reports now (nil: none). It
    /// catches a start or an end missed while AutoHush was quit. The Focus
    /// the saved note already follows, seen again, changes nothing: applying
    /// its choice again would override what the user set by hand since.
    func followAtLaunch(_ choice: Bool?, now: Date = Date()) {
        if let choice, preferences.focusAutoPause?.applied == choice { return }
        follow(choice, now: now)
    }
}
