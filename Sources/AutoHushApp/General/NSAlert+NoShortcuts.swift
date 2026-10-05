import AppKit

extension NSAlert {
    /// Runs the alert without keyboard shortcuts: AutoHush has none, and
    /// AppKit would give the first button Return. That button keeps its
    /// accent color.
    @discardableResult
    func runModalWithoutShortcuts() -> NSApplication.ModalResponse {
        for (index, button) in buttons.enumerated() {
            button.keyEquivalent = ""
            if index == 0 { button.bezelColor = .controlAccentColor }
        }
        return runModal()
    }
}
