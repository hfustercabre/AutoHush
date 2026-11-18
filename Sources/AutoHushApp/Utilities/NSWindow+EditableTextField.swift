import AppKit

extension NSWindow {
    /// The first text field under `view` takes the keyboard, the caret after
    /// its text: a window's search, one of Tab's stops (K3); `false` when
    /// none shows. One place for the guiding windows', Settings' page and the
    /// logs' (R-2 of 11-11).
    @MainActor
    func focusFirstEditableTextField(in view: NSView?) -> Bool {
        guard let field = view?.firstEditableTextField, makeFirstResponder(field) else { return false }
        field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        return true
    }
}
