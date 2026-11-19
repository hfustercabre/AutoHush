import Testing
@testable import WebAppPlayers

@Suite("SafariTab")
struct SafariTabTests {
    private static func tab(window: Int = 0, button: Int?, page: Int?) -> SafariTab {
        SafariTab(window: window, button: button, page: page)
    }

    @Test("a tab read again is the same tab after a page loads in it (its button stays, F2 of 1.4.2's review), and after a second tab gives its window a tab bar (its page stays, C-1 of 1.4.3's review)")
    func sameTab() {
        #expect(Self.tab(button: 1, page: 10).isSame(as: Self.tab(button: 1, page: 11)))
        #expect(Self.tab(button: nil, page: 10).isSame(as: Self.tab(button: 1, page: 10)))
        #expect(Self.tab(button: 1, page: 10).isSame(as: Self.tab(button: nil, page: 10)))
    }

    @Test("another tab of the window, a tab of another window, a window's only tab once its page changed (left open, P-2 of 1.4.3's review) and no tab aren't the same tab")
    func otherTab() {
        #expect(!Self.tab(button: 1, page: 10).isSame(as: Self.tab(button: 2, page: 20)))
        #expect(!Self.tab(button: nil, page: 10).isSame(as: Self.tab(button: 2, page: 20)))
        #expect(!Self.tab(window: 0, button: 1, page: 10).isSame(as: Self.tab(window: 1, button: 1, page: 10)))
        #expect(!Self.tab(button: nil, page: 10).isSame(as: Self.tab(button: nil, page: 11)))
        #expect(!Self.tab(button: nil, page: nil).isSame(as: Self.tab(button: nil, page: nil)))
        #expect(!Self.tab(button: 1, page: 10).isSame(as: nil))
    }
}
