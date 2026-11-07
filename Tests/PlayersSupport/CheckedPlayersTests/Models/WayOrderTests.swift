import Testing
@testable import CheckedPlayers
import AutoHushKit
import AutoHushTestSupport

@Suite("WayOrder")
struct WayOrderTests {
    /// How a way did in the states given (the others not tested).
    private func result(_ kind: CheckResult.WayKind, _ found: [CheckResult.WindowState: CheckResult.StateResult.Outcome]) -> CheckResult.WayResult {
        CheckResult.WayResult(kind: kind, mark: .some,
                              states: CheckResult.WindowState.allCases.compactMap { state in found[state].map { .init(state: state, outcome: $0) } })
    }

    /// Worked in every state of the trip.
    private func everywhere(_ kind: CheckResult.WayKind) -> CheckResult.WayResult {
        CheckResult.WayResult(kind: kind, mark: .works, states: CheckResult.WindowState.trip.map { .init(state: $0, outcome: .worked) })
    }

    @Test("the chosen way first where it worked, then the other quiet ways that worked there, those not tested there, the panel last; a way that failed there is left out")
    func order() {
        let ways = WayOrder(ways: [
            .init(kind: .page, result: result(.page, [.visible: .worked, .minimized: .failed])),
            .init(kind: .panel, result: everywhere(.panel)),
            .init(kind: .menu, result: result(.menu, [.visible: .worked, .minimized: .worked])),
            .init(kind: .script, result: nil),
        ])
        #expect(ways.order(in: .visible, for: .paused) == [0, 2, 3, 1])
        #expect(ways.order(in: .minimized, for: .paused) == [2, 3, 1])
        // Neither the page nor the menu tried hidden: both among the untested, the chosen first.
        #expect(ways.order(in: .hidden, for: .paused) == [0, 2, 3, 1])
        #expect(ways.order(in: .minimized, for: .playing) == [2, 3, 1])
    }

    @Test("another main control chosen takes the chosen way's place; only one that worked can be, never the Play/Pause key")
    func chosenMain() {
        let ways = WayOrder(ways: [
            .init(kind: .script, result: everywhere(.script)),
            .init(kind: .menu, result: everywhere(.menu)),
            .init(kind: .page, result: result(.page, [.visible: .worked, .hidden: .failed])),
            .init(kind: .mediaKey, result: nil),
            .init(kind: .panel, result: everywhere(.panel)),
        ])
        #expect(ways.mainIndex(for: "menu") == 1 && ways.mainIndex(for: "panel") == 4)
        #expect(ways.mainIndex(for: "mediaKey") == 0 && ways.mainIndex(for: nil) == 0 && ways.mainIndex(for: "script") == 0)
        #expect(ways.order(in: .visible, for: .paused, main: 1) == [1, 0, 2, 3, 4])
        // The page chosen, hidden where it failed: the others, its own first.
        #expect(ways.order(in: .hidden, for: .paused, main: 2) == [0, 1, 3, 4])
        // The panel chosen: first, then the others in their order.
        #expect(ways.order(in: .visible, for: .paused, main: 4) == [4, 0, 1, 2, 3])
        let untested = WayOrder(ways: [.init(kind: .script, result: nil), .init(kind: .menu, result: nil)])
        #expect(untested.mainIndex(for: "menu") == 0) // not known to work
    }

    @Test("the Play/Pause key, which no check tests, comes after the other untested ways, before the panel, in every state")
    func mediaKey() {
        let ways = WayOrder(ways: [
            .init(kind: .page, result: result(.page, [.visible: .worked, .minimized: .failed])),
            .init(kind: .panel, result: everywhere(.panel)),
            .init(kind: .script, result: nil),
            .init(kind: .mediaKey, result: nil),
        ])
        #expect(ways.order(in: .visible, for: .paused) == [0, 2, 3, 1])
        #expect(ways.order(in: .minimized, for: .playing) == [2, 3, 1])
        let keyOnly = WayOrder(ways: [.init(kind: .menu, result: result(.menu, [.hidden: .failed])), .init(kind: .mediaKey, result: nil)])
        #expect(keyOnly.order(in: .hidden, for: .paused) == [1])
        #expect(WayOrder.Kind.mediaKey.checked == nil && WayOrder.Kind(.panel) == .panel && WayOrder.Kind.mediaKey.logName == "Play/Pause key")
    }

    @Test("a chosen panel that worked there comes first; when every way failed there, the chosen one is still pressed")
    func panelAndNoneLeft() {
        let panelFirst = WayOrder(ways: [.init(kind: .panel, result: everywhere(.panel)), .init(kind: .menu, result: everywhere(.menu))])
        #expect(panelFirst.order(in: .covered, for: .paused) == [0, 1])
        let failing = WayOrder(ways: [.init(kind: .menu, result: result(.menu, [.hidden: .failed])),
                                      .init(kind: .panel, result: result(.panel, [.hidden: .failed]))])
        #expect(failing.order(in: .hidden, for: .paused) == [0])
    }

    @Test("a way that only paused the app there is pressed for a pause, not for a play")
    func pausedOnly() {
        let ways = WayOrder(ways: [.init(kind: .page, result: result(.page, [.visible: .pausedOnly])),
                                   .init(kind: .menu, result: result(.menu, [.visible: .worked]))])
        #expect(ways.order(in: .visible, for: .paused) == [0, 1])
        #expect(ways.order(in: .visible, for: .playing) == [1])
    }

    @Test("a check saved before its states were kept goes by its mark and the states it failed in; a setup with no results is untested everywhere")
    func olderResults() {
        let page = CheckResult.WayResult(kind: .page, mark: .some, failedStates: [.minimized])
        #expect(page.outcome(in: .minimized) == .failed && page.outcome(in: .covered) == .worked)
        #expect(CheckResult.WayResult(kind: .panel, mark: .works).outcome(in: .hidden) == .worked)
        #expect(CheckResult.WayResult(kind: .menu, mark: .notTried).outcome(in: .visible) == .untested)
        let ways = WayOrder(ways: [.init(kind: .page, result: page), .init(kind: .menu, result: nil)])
        #expect(ways.order(in: .visible, for: .paused) == [0, 1])
        #expect(ways.order(in: .minimized, for: .paused) == [1])
    }

    @Test("the window is looked at only when the order changes with its state")
    func dependsOnWindow() {
        #expect(!WayOrder(ways: [.init(kind: .page, result: everywhere(.page)), .init(kind: .panel, result: everywhere(.panel))])
            .dependsOnWindow(for: .paused))
        #expect(WayOrder(ways: [.init(kind: .page, result: result(.page, [.visible: .worked, .hidden: .failed])),
                                .init(kind: .panel, result: everywhere(.panel))]).dependsOnWindow(for: .paused))
        #expect(!WayOrder(ways: [.init(kind: .menu, result: result(.menu, [.hidden: .failed]))]).dependsOnWindow(for: .paused))
    }
}
