import Foundation

/// The tab `SafariDriving` opened a website in, to close it afterwards.
package struct SafariTab: @unchecked Sendable {
    /// Its page's Accessibility element (a number in tests).
    let page: AnyHashable

    init(page: AnyHashable) {
        self.page = page
    }
}
