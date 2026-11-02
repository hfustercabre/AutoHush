import Foundation

/// One of a page's buttons, the same between looks while the page isn't
/// reloaded. Holds the button's Accessibility element; a number in tests.
/// `@unchecked Sendable`: an `AXUIElement` is an immutable CoreFoundation
/// object, used from any thread, and the handle only compares it and hands
/// it back; nothing else may go in `element`.
package struct ButtonHandle: Hashable, @unchecked Sendable {
    let element: AnyHashable

    package init(_ element: AnyHashable) {
        self.element = element
    }
}
