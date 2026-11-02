import Foundation

/// The tab `SafariDriving` opened a website in, to close it afterwards.
/// `@unchecked Sendable`: its page is an `AXUIElement`, an immutable
/// CoreFoundation object used from any thread, only compared and handed
/// back (a number in tests); nothing else may go in it.
package struct SafariTab: @unchecked Sendable {
    /// Its page's Accessibility element (a number in tests).
    let page: AnyHashable

    init(page: AnyHashable) {
        self.page = page
    }
}
