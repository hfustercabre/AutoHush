import AppKit
import Testing
@testable import AutoHushApp

@Suite("RadioChoices")
@MainActor
struct RadioChoicesTests {
    /// A stack of three radio buttons, the middle one dimmed, laid out in a
    /// container; records choices and clicks on the dimmed one.
    @MainActor
    private final class Harness {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let stack = RadioStack()
        var chosen: [Int] = []
        var unavailableClicks = 0

        init(reportsUnavailableClicks: Bool = true) {
            container.addSubview(stack)
            stack.update(titles: ["Notify me", "Download it and notify me", "Install it automatically"],
                         enabled: [true, false, true], selected: 2)
            stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
            stack.layoutSubtreeIfNeeded()
            stack.onSelect = { [unowned self] in chosen.append($0) }
            if reportsUnavailableClicks { stack.onUnavailableClick = { [unowned self] in unavailableClicks += 1 } }
        }

        /// What a click in the middle of button `index` lands on.
        func hit(_ index: Int) -> NSView? {
            let button = stack.buttons[index]
            let center = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
            return stack.hitTest(button.convert(center, to: container))
        }
    }

    @Test("each option is a radio button with its title, availability and selection")
    func buttons() {
        let h = Harness()
        #expect(h.stack.buttons.map(\.title) == ["Notify me", "Download it and notify me", "Install it automatically"])
        #expect(h.stack.buttons.map(\.isEnabled) == [true, false, true])
        #expect(h.stack.buttons.map(\.state) == [.off, .off, .on])
    }

    @Test("clicking an available option chooses it")
    func choose() {
        let h = Harness()
        h.stack.buttons[0].performClick(nil)
        #expect(h.chosen == [0])
        #expect(h.hit(0).map { $0 === h.stack } == false)
    }

    @Test("a click on a dimmed option is taken by the stack and reported")
    func unavailableClick() throws {
        let h = Harness()
        let target = try #require(h.hit(1))
        #expect(target === h.stack)
        target.mouseDown(with: try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )))
        #expect(h.unavailableClicks == 1)
        #expect(h.chosen.isEmpty)
    }

    @Test("clicks between or beside the options belong to none of them")
    func clicksOutsideOptions() {
        let h = Harness()
        let (first, second) = (h.stack.buttons[0].frame, h.stack.buttons[1].frame)
        // Halfway across the space between the first two buttons, whichever way up.
        let between = NSPoint(x: 4, y: (max(first.minY, second.minY) + min(first.maxY, second.maxY)) / 2)
        // Right of "Notify me", the shortest title, within the stack.
        let beside = NSPoint(x: h.stack.bounds.maxX - 2, y: first.midY)
        for point in [between, beside] {
            #expect(h.stack.hitTest(h.stack.convert(point, to: h.container)) == nil)
        }
    }

    @Test("when the whole group is disabled, clicks on dimmed options aren't taken")
    func groupDisabled() {
        let h = Harness(reportsUnavailableClicks: false)
        #expect(h.hit(1).map { $0 === h.stack } == false)
    }
}
