import ApplicationServices
import Testing
@testable import PlayerCheck

/// A page button's hit test, judged as the check judges it (`hitShowsUncovered`).
@Suite("playercheck: a page button's hit test", .readOnlyRun)
struct PageTests {
    /// Stand-ins for a page's elements, each its own (`CFEqual` by pid): a
    /// player's bar (an audio element) holding Play/Pause and its icon, a
    /// song tile's Play in a list, and a cover over them, in the page.
    private let window = AXUIElementCreateApplication(90_001), page = AXUIElementCreateApplication(90_002)
    private let main = AXUIElementCreateApplication(90_003), bar = AXUIElementCreateApplication(90_004)
    private let button = AXUIElementCreateApplication(90_005), icon = AXUIElementCreateApplication(90_006)
    private let list = AXUIElementCreateApplication(90_007), tile = AXUIElementCreateApplication(90_008)
    private let cover = AXUIElementCreateApplication(90_009)

    private func parent(_ element: AXUIElement) -> AXUIElement? {
        let parents = [(page, window), (main, page), (bar, main), (button, bar), (icon, button), (list, main), (tile, list), (cover, page)]
        return parents.first { CFEqual($0.0, element) }?.1
    }

    /// The judgment of a hit on `hit`, and whether it read the bar around `of`.
    private func judged(_ of: AXUIElement, hit: AXUIElement, barAround: AXUIElement?) -> (uncovered: Bool, barRead: Bool) {
        var barRead = false
        let uncovered = hitShowsUncovered(of, hit: hit, parent: parent, bar: { barRead = true; return barAround })
        return (uncovered, barRead)
    }

    @Test("the button or inside it answers: uncovered, its bar not read; something else over it answers: covered")
    func buttonOrCover() {
        #expect(judged(button, hit: button, barAround: bar) == (true, false))
        #expect(judged(button, hit: icon, barAround: bar) == (true, false))
        #expect(judged(button, hit: cover, barAround: bar) == (false, false))
    }

    @Test("its player's bar answers, or a parent of it a little higher (Chromium's media controls): uncovered; a parent of a song tile, with no bar around, or one too far up: covered")
    func parentAnswers() {
        // L1, 2026-10-30: Chromium answers an audio element's Play/Pause with the element.
        #expect(judged(button, hit: bar, barAround: bar) == (true, true))
        #expect(judged(button, hit: main, barAround: bar) == (true, true))
        #expect(judged(tile, hit: list, barAround: nil) == (false, true))
        #expect(judged(tile, hit: bar, barAround: nil) == (false, false))
        #expect(judged(button, hit: window, barAround: bar) == (false, false)) // its fourth parent
    }
}

/// What a press by the page may learn from (`isPlayersButton`), with the
/// page the tool found (`page`) set as a test needs it.
@Suite("playercheck: what a page press learns from", .readOnlyRun)
@MainActor
struct PagePressLearningTests {
    /// Stand-ins: the player bar's Play/Pause, the bar around it, and a song tile's Pause.
    private let button = AXUIElementCreateApplication(90_201), bar = AXUIElementCreateApplication(90_202)
    private let tile = AXUIElementCreateApplication(90_203)

    @Test("a press learns its words from the player's own Play/Pause only: the button learned or the player bar's, or one with a player bar around it; never a song tile named Play or Pause")
    func pressLearnsFromPlayersButton() {
        let (found, foundBar, foundLearned) = (page, barToggle, learned)
        defer { (page, barToggle, learned) = (found, foundBar, foundLearned) }
        (barToggle, learned) = (nil, nil)
        func shown(_ element: AXUIElement, withControls: Bool) -> PageCheck {
            PageCheck(buttons: 2, toggle: FoundButton(element: element, label: "Pause", fromBottom: nil, inSight: true, onScreen: true),
                      withControls: withControls)
        }
        let around = bar
        // The page's only Pause is a song tile's: no player bar around it.
        page = shown(tile, withControls: false)
        let tileTaught = isPlayersButton(tile, bar: { _ in nil }), barred = isPlayersButton(button, bar: { _ in around })
        #expect(!tileTaught && barred)
        // The player bar's button, found where it was learned.
        page = shown(button, withControls: true)
        let barsOwn = isPlayersButton(button, bar: { _ in nil }), tileThen = isPlayersButton(tile, bar: { _ in nil })
        #expect(barsOwn && !tileThen)
    }
}
