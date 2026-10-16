import AppKit

extension NSView {
    /// The first text field one can type into, in this view or under it.
    @MainActor
    var firstEditableTextField: NSTextField? {
        if let field = self as? NSTextField, field.isEditable { return field }
        return subviews.lazy.compactMap(\.firstEditableTextField).first
    }
}
