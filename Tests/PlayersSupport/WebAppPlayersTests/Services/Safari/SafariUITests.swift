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

    @Test("the open dialog counts as closed only after three misses in a row with Safari answering; a look Safari didn't answer, or one finding it, never closes it (checked-webapps-5)",
          arguments: [([SafariUI.DialogLook.absent, .absent, .absent], true), ([.absent], false), ([.absent, .absent], false),
                      ([.absent, .absent, .shown, .absent, .absent], false), ([.unreadable, .unreadable, .unreadable, .unreadable], false),
                      ([.absent, .unreadable, .absent, .unreadable, .absent], true)])
    func dialogWatch(_ looks: [SafariUI.DialogLook], _ closed: Bool) {
        var watch = SafariUI.DialogWatch()
        let closes = looks.map { watch.closes(after: $0) }
        #expect(closes.last == closed)
        #expect(!closes.dropLast().contains(true))
    }
}
