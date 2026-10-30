import Foundation

/// One of a page's buttons, the same between looks while the page isn't
/// reloaded. Holds the button's Accessibility element; a number in tests.
package struct ButtonHandle: Hashable, @unchecked Sendable {
    let element: AnyHashable

    package init(_ element: AnyHashable) {
        self.element = element
    }
}
