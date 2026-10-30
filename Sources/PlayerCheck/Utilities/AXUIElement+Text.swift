import AppKit
import AutoHushKit

// MARK: - Accessibility, as AutoHush reads it

// AutoHushKit's `value(_:)`, `string(_:)`, `children`, `frame` and
// `actionNames` read attributes, as AutoHush's players do;
// `AXUIElement.application(_:timeout:)` gives an app's element its timeout.
extension AXUIElement {
    var title: String { text(kAXTitleAttribute) }
    func text(_ attribute: String) -> String { string(attribute) ?? "" }
}
