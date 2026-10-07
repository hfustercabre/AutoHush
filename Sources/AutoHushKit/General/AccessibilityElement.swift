import ApplicationServices

/// Reading another app's interface through Accessibility: the few calls the
/// players that press buttons (TIDAL's and Podcasts' menus, web apps' pages,
/// Safari's Add to Dock) all need.
extension AXUIElement {
    /// The attribute's value; `nil` when it has none or the app doesn't answer.
    package func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success ? value : nil
    }

    /// The attribute's value, when it's an element (a parent, a window…).
    package func element(_ attribute: String) -> AXUIElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// The attribute's value, when it's a list of elements.
    package func elements(_ attribute: String) -> [AXUIElement] {
        AXUIElement.elements(in: value(attribute))
    }

    package var children: [AXUIElement] { elements(kAXChildrenAttribute) }

    package func string(_ attribute: String) -> String? { value(attribute) as? String }

    /// The elements in a value (an attribute's, a search's result).
    package static func elements(in value: CFTypeRef?) -> [AXUIElement] {
        (value as? [AnyObject] ?? []).compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }
}
