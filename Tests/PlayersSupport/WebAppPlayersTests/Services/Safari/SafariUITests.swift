import Testing
@testable import WebAppPlayers

@Suite("SafariUI")
struct SafariUITests {
    @Test("closing a tab presses Close Tab, Close Window only for a window's only tab (Close Tab off, no other tab), and nothing when Close Tab is off in a window of several tabs (C-3 of 1.4.3's review)",
          arguments: [(true as Bool?, true, SafariUI.ClosingPress.closeTab as SafariUI.ClosingPress?), (true, false, .closeTab),
                      (nil, true, .closeTab), (false, false, .closeWindow), (false, true, nil)])
    func closingPress(_ closeTabEnabled: Bool?, _ otherTabs: Bool, _ press: SafariUI.ClosingPress?) {
        #expect(SafariUI.closingPress(closeTabEnabled: closeTabEnabled, otherTabs: otherTabs) == press)
    }

    @Test("a window may hold other tabs with two or more tab buttons, and when its tab bar couldn't be read; not without a tab bar or with one button (Compact's only tab) (I2 of 1.4.3's diff review)",
          arguments: [(SafariUI.TabBar.absent, false), (.tabs(1), false), (.tabs(2), true), (.tabs(9), true), (.unreadable, true)])
    func mayHoldOtherTabs(_ bar: SafariUI.TabBar, _ others: Bool) {
        #expect(bar.mayHoldOtherTabs == others)
    }
}
