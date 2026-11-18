import SwiftUI
import Testing
@testable import AutoHushApp

@Suite("SearchField")
struct SearchFieldTests {
    @Test("in an empty search, the arrow back out of it (to close the menu's side window) is ← left to right and → right to left (Arabic, Hebrew), as macOS's menus close a submenu; the other arrow, and any other key, isn't (F6 of 1.4.2's review)",
          arguments: [(KeyEquivalent.leftArrow, LayoutDirection.leftToRight, true), (.rightArrow, .leftToRight, false),
                      (.rightArrow, .rightToLeft, true), (.leftArrow, .rightToLeft, false),
                      (.upArrow, .leftToRight, false), (.downArrow, .rightToLeft, false)])
    func backKey(_ key: KeyEquivalent, _ layout: LayoutDirection, _ back: Bool) {
        #expect(SearchField.goesBack(key, in: layout) == back)
    }
}
