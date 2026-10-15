import AppKit
import AutoHushKit

// UpdateController: the user's settings.
extension UpdateController {
    /// Checks by itself once a day, or not, as the user chose in Settings;
    /// turned on, it checks at once if a check is due.
    func setChecksAutomatically(_ enabled: Bool) {
        checksAutomatically = enabled
        onSettingsChange()
        if enabled { Task { await runAutomaticTasks() } }
    }

    /// Stores what automatic checks lead to, and acts on an update already
    /// found the new way (e.g. downloads it). A choice that notifies asks for
    /// permission to, if the user hasn't answered yet.
    func setMode(_ newMode: AutomaticUpdates) {
        mode = newMode
        onSettingsChange()
        if newMode != .install { notifier.requestPermission() }
        Task { await runAutomaticTasks() }
    }
}
