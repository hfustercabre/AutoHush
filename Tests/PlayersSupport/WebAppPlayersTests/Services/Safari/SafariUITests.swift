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
}
