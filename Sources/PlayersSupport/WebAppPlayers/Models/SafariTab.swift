import Foundation

/// A tab of Safari's, as `SafariDriving` tells it from the others: the tab
/// opened for a website, to close it afterwards, or the user's own, never
/// closed. A page loading in the tab keeps it the same, unlike the page
/// itself (F2 of 1.4.2's review). `@unchecked Sendable`: its identity is
/// made of `AXUIElement`s, immutable CoreFoundation objects used from any
/// thread, only compared and handed back (a number in tests); nothing else
/// may go in it.
package struct SafariTab: @unchecked Sendable, Equatable {
    /// What tells it from Safari's other tabs (a number in tests).
    let id: AnyHashable

    init(id: AnyHashable) {
        self.id = id
    }
}
