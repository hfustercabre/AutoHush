import Testing
@testable import CheckedPlayers

@Suite("AccessibilityNowPlayingPanel")
struct AccessibilityNowPlayingPanelTests {
    @Test("its menu bar item is looked for in the menu bar's own windows, then hit-tested along it; with Now Playing hidden, never hit-tested: macOS removes a hidden item")
    func itemHiddenSkipsTheSweep() {
        var swept = 0
        func sweep() -> Int? {
            swept += 1
            return 2
        }
        #expect(AccessibilityNowPlayingPanel.item(hidden: false, listed: { nil }, hitTested: sweep) == 2)
        #expect(swept == 1)
        #expect(AccessibilityNowPlayingPanel.item(hidden: false, listed: { 1 }, hitTested: sweep) == 1)
        #expect(AccessibilityNowPlayingPanel.item(hidden: true, listed: { nil }, hitTested: sweep) == nil)
        #expect(AccessibilityNowPlayingPanel.item(hidden: true, listed: { 1 }, hitTested: sweep) == 1)
        #expect(swept == 1)
    }
}
