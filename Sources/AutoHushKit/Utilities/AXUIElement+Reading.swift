import ApplicationServices

/// Reading another app's interface through Accessibility: the few calls the
/// players that press buttons (an app's playback menu, a web app's page,
/// the browser's Add to Dock) all need.
///
/// How long a read waits for the app is set per element: Apple's header says
/// a timeout set on an element holds for that element only (not even for
/// others equal to it), so those read from it wait macOS's default (6 s). A
/// walk that must not hang on a busy app reads with `element(_:timeout:)`,
/// `elements(_:timeout:)` or `children(timeout:)`, which set it on each
/// element they return.
extension AXUIElement {
    /// The app running as `pid`, whose reads wait at most `timeout` seconds.
    package static func application(_ pid: pid_t, timeout: Float) -> AXUIElement {
        AXUIElementCreateApplication(pid).waiting(timeout)
    }

    /// Sets how long a read of this element waits for its app to answer, in
    /// seconds; the element itself.
    @discardableResult
    package func waiting(_ timeout: Float) -> AXUIElement {
        AXUIElementSetMessagingTimeout(self, timeout)
        return self
    }

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

    /// The attribute's element, its reads waiting at most `timeout` seconds.
    package func element(_ attribute: String, timeout: Float) -> AXUIElement? {
        element(attribute)?.waiting(timeout)
    }

    /// The attribute's elements, each one's reads waiting at most `timeout` seconds.
    package func elements(_ attribute: String, timeout: Float) -> [AXUIElement] {
        elements(attribute).map { $0.waiting(timeout) }
    }

    /// Its children, each one's reads waiting at most `timeout` seconds.
    package func children(timeout: Float) -> [AXUIElement] { elements(kAXChildrenAttribute, timeout: timeout) }

    package func string(_ attribute: String) -> String? { value(attribute) as? String }

    /// Its frame on screen, from the top left corner; `nil` without one.
    package var frame: CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = value(kAXPositionAttribute), let extent = value(kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(extent) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(extent as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The actions it offers (AXPress…).
    package var actionNames: [String] {
        var names: CFArray?
        return AXUIElementCopyActionNames(self, &names) == .success ? names as? [String] ?? [] : []
    }

    /// The elements in a value (an attribute's, a search's result).
    package static func elements(in value: CFTypeRef?) -> [AXUIElement] {
        (value as? [AnyObject] ?? []).compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }
}
