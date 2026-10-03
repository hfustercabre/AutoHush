import AppKit
import AutoHushKit

extension SystemSettingsPane {
    /// Opens the pane in System Settings.
    @MainActor
    func open() {
        NSWorkspace.shared.open(url)
    }
}
