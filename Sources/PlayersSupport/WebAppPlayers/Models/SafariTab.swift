import Foundation

/// A tab of Safari's, as `SafariDriving` tells it from the others: the tab
/// opened for a website, to close it afterwards, or the user's own, never
/// closed. Read as its window, its selected tab button and its page:
/// a page loading in the tab keeps the button and takes another page (F2 of
/// 1.4.2's review); a window of one tab shows no button (Separate tab
/// layout) until a second tab opens in it, while its page stays (C-1 of 1.4.3's review). So `isSame`
/// asks for the same window and either of the other two. `@unchecked
/// Sendable`: its parts are `AXUIElement`s, immutable CoreFoundation objects
/// used from any thread, only compared (numbers in tests); nothing else may
/// go in it.
package struct SafariTab: @unchecked Sendable {
    let window: AnyHashable
    /// Its button in the window's tab bar; none in a window of one tab
    /// (Separate tab layout).
    let button: AnyHashable?
    /// The page it shows; none when it can't be read.
    let page: AnyHashable?

    init(window: AnyHashable, button: AnyHashable?, page: AnyHashable?) {
        self.window = window
        self.button = button
        self.page = page
    }

    /// Whether `other` is this tab, read again: the same window, and the same
    /// button or the same page. `nil` is no tab.
    func isSame(as other: SafariTab?) -> Bool {
        guard let other, other.window == window else { return false }
        if let button, let otherButton = other.button, button == otherButton { return true }
        if let page, let otherPage = other.page, page == otherPage { return true }
        return false
    }
}
