import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

extension StatusMenuControllerTests {
    /// The menu open with two players, First and Second.
    private func menuWithTwoPlayers() -> StatusMenuController {
        let sut = makeController()
        var status = readyStatus()
        status.playerOptions = ["First", "Second"].map {
            PlayerOption(bundleID: "com.example.\($0)", name: $0, appURL: URL(fileURLWithPath: "/Applications/\($0).app"))
        }
        sut.status = status
        reopen(sut)
        return sut
    }

    /// The players' list open, its rows registered as the side window's views register them.
    private func twoPlayerRows(_ sut: StatusMenuController) -> (first: UUID, second: UUID) {
        sut.perform(.openSide(.players))
        let first = UUID(), second = UUID()
        sut.model.sideKeyboard.register(first, .init(frame: CGRect(x: 0, y: 0, width: 280, height: 22),
                                                     press: { sut.perform(.choosePlayer("com.example.First")) }))
        sut.model.sideKeyboard.register(second, .init(frame: CGRect(x: 0, y: 30, width: 280, height: 22),
                                                      press: { sut.perform(.choosePlayer("com.example.Second")) }))
        return (first, second)
    }

    @Test("with the players folded, a key the menu has no use for is left to the panel")
    func playerKeys() {
        let sut = menuWithTwoPlayers()
        defer { sut.remove() }
        #expect(!sut.handleKey(MenuPanelTests.key(0)))
    }

    @Test("among the players, ← closes them")
    func leftClosesPlayers() {
        let sut = menuWithTwoPlayers()
        defer { sut.remove() }
        sut.perform(.openSide(.players))
        #expect(sut.handleKey(MenuPanelTests.key(123))) // ←
        #expect(!sut.model.isChoosingPlayer)
    }

    @Test("among the players, Return with nothing highlighted and nothing typed chooses nothing")
    func returnWithNoPlayerHighlighted() {
        let sut = menuWithTwoPlayers()
        defer { sut.remove() }
        sut.perform(.openSide(.players))
        sut.handle(.returnKey) // nothing highlighted, nothing typed: nothing chosen
        #expect(sut.model.isChoosingPlayer)
    }

    @Test("among the players, ↑ ↓ move the side window's highlight through their rows, the menu's staying put; other keys aren't the list's")
    func arrowsMoveThroughPlayers() {
        let sut = menuWithTwoPlayers()
        defer { sut.remove() }
        let (first, _) = twoPlayerRows(sut)
        #expect(sut.handleKey(MenuPanelTests.key(125))) // ↓
        #expect(sut.model.sideKeyboard.highlighted == first)
        #expect(sut.model.keyboard.highlighted == nil) // the menu's stays where it was
        #expect(sut.handleKey(MenuPanelTests.key(125)))
        #expect(sut.handleKey(MenuPanelTests.key(126))) // ↑
        #expect(sut.model.sideKeyboard.highlighted == first)
        #expect(!sut.handleKey(MenuPanelTests.key(0))) // A: not the list's
    }

    @Test("among the players, the search field's ↓ and ↑ move the side window's highlight too")
    func searchFieldMovesThroughPlayers() {
        let sut = menuWithTwoPlayers()
        defer { sut.remove() }
        let (first, second) = twoPlayerRows(sut)
        #expect(sut.handleKey(MenuPanelTests.key(125))) // ↓
        sut.perform(.moveHighlight(1)) // as the search field's ↓ sends it
        #expect(sut.model.sideKeyboard.highlighted == second)
        sut.perform(.moveHighlight(-1))
        #expect(sut.model.sideKeyboard.highlighted == first)
    }

    @Test("among the players, Return presses the one the highlight is on")
    func returnChoosesHighlightedPlayer() async {
        let sut = menuWithTwoPlayers()
        defer { sut.remove() }
        _ = twoPlayerRows(sut)
        #expect(sut.handleKey(MenuPanelTests.key(125))) // ↓: the first
        #expect(sut.handleKey(MenuPanelTests.key(36))) // Return
        await wait(for: 2, in: log)
        #expect(log.calls == ["menuWillOpen", "player com.example.First"])
    }

    /// The menu open, with Ignored Apps listing Viewer, and two rows its views
    /// registered (what they pressed in `presses`): a slider, then the row that opens Ignored Apps' side
    /// window. The keys work as in macOS's menus, whatever the keyboard
    /// navigation setting.
    private func menuWithRows() -> (sut: StatusMenuController, presses: CallLog, slider: UUID, sideRow: UUID) {
        let sut = menuIgnoringAnApp()
        let presses = CallLog()
        let slider = UUID(), sideRow = UUID()
        sut.model.keyboard.register(slider, .init(frame: CGRect(x: 0, y: 0, width: 300, height: 20), adjust: { presses.calls.append("adjust \($0)") }))
        sut.model.keyboard.register(sideRow, .init(frame: CGRect(x: 0, y: 40, width: 300, height: 20),
                                                   press: { sut.perform(.openSide(.ignoredApps)) }, opensSide: true))
        return (sut, presses, slider, sideRow)
    }

    @Test("in the menu, ↓ moves the highlight to its first control, as in macOS's menus")
    func downMovesHighlight() {
        let (sut, _, slider, _) = menuWithRows()
        defer { sut.remove() }
        #expect(sut.handleKey(MenuPanelTests.key(125))) // ↓: the first
        #expect(sut.model.keyboard.highlighted == slider)
    }

    @Test("in the menu, Return on a control with nothing to press does nothing, without a beep")
    func returnWithNothingToPress() {
        let (sut, presses, _, _) = menuWithRows()
        defer { sut.remove() }
        #expect(sut.handleKey(MenuPanelTests.key(125)))
        #expect(sut.handleKey(MenuPanelTests.key(36))) // Return: nothing to press, and no beep
        #expect(presses.calls.isEmpty)
    }

    @Test("in the menu, → and ← adjust a slider")
    func arrowsAdjust() {
        let (sut, presses, _, _) = menuWithRows()
        defer { sut.remove() }
        #expect(sut.handleKey(MenuPanelTests.key(125)))
        #expect(sut.handleKey(MenuPanelTests.key(124))) // →
        #expect(sut.handleKey(MenuPanelTests.key(123))) // ←
        #expect(presses.calls == ["adjust 1", "adjust -1"])
    }

    @Test("in the menu, → opens a side window from its row, on its first row once they've come; ↓ goes on from it, Space presses, and ← closes it")
    func arrowsOpenAndCloseSide() async {
        let (sut, presses, _, sideRow) = menuWithRows()
        defer { sut.remove() }
        let keyboard = sut.model.keyboard
        let appRow = UUID(), addRow = UUID()
        #expect(sut.handleKey(MenuPanelTests.key(125)))
        #expect(sut.handleKey(MenuPanelTests.key(125)))
        #expect(sut.handleKey(MenuPanelTests.key(124))) // → opens its side window
        #expect(sut.model.openSide == .ignoredApps)

        // Its rows, as its views register them: the first lights up once they've come.
        sut.model.sideKeyboard.register(addRow, .init(frame: CGRect(x: 0, y: 40, width: 280, height: 30), press: { presses.calls.append("add") }))
        sut.model.sideKeyboard.register(appRow, .init(frame: CGRect(x: 0, y: 0, width: 280, height: 30), press: { presses.calls.append("app") }))
        await TestWait.until { sut.model.sideKeyboard.highlighted == appRow }
        #expect(keyboard.highlighted == sideRow)
        #expect(sut.handleKey(MenuPanelTests.key(125))) // ↓ goes on from it
        #expect(sut.model.sideKeyboard.highlighted == addRow)
        #expect(sut.handleKey(MenuPanelTests.key(49))) // Space
        #expect(presses.calls.last == "add")
        #expect(sut.handleKey(MenuPanelTests.key(123))) // ← closes it
        #expect(sut.model.openSide == nil)
        #expect(sut.model.sideKeyboard.highlighted == nil)
        #expect(keyboard.highlighted == sideRow)
    }

    @Test("in a side window the pointer opened, → lights its first row")
    func rightLightsPointerOpenedSide() {
        let (sut, _, _, _) = menuWithRows()
        defer { sut.remove() }
        let appRow = UUID()
        sut.perform(.openSide(.ignoredApps))
        sut.model.sideKeyboard.register(appRow, .init(frame: CGRect(x: 0, y: 0, width: 280, height: 30), press: {}))
        #expect(sut.handleKey(MenuPanelTests.key(124)))
        #expect(sut.model.sideKeyboard.highlighted == appRow)
    }

    @Test("in the menu, Tab leaves the highlight to the keyboard's focus; a menu opens with nothing highlighted")
    func tabLeavesToFocus() {
        let (sut, _, _, _) = menuWithRows()
        defer { sut.remove() }
        let keyboard = sut.model.keyboard
        #expect(sut.handleKey(MenuPanelTests.key(125)))
        #expect(!sut.handleKey(MenuPanelTests.key(48))) // Tab: the keyboard's focus takes over
        #expect(keyboard.highlighted == nil)
        keyboard.move(1)
        reopen(sut) // a menu opens with nothing highlighted
        #expect(keyboard.highlighted == nil)
    }

    /// A key down with `characters`, as `ignoring` modifiers if they differ.
    static func keyDown(_ characters: String, ignoring: String? = nil, code: UInt16 = 0,
                        flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                                      characters: characters, charactersIgnoringModifiers: ignoring ?? characters,
                                      isARepeat: false, keyCode: code))
    }

    @Test("what a key types into the players' search: its characters, Delete one back, nothing for arrows, Return or shortcuts")
    func typing() throws {
        #expect(StatusMenuController.typedText(try Self.keyDown("é")) == "é")
        #expect(StatusMenuController.typedText(try Self.keyDown("\u{7f}", code: 51)) == "") // Delete
        #expect(StatusMenuController.typedText(try Self.keyDown("\u{F701}", code: 125)) == nil) // ↓
        #expect(StatusMenuController.typedText(try Self.keyDown("\r", code: 36)) == nil)
        #expect(StatusMenuController.typedText(try Self.keyDown("a", flags: .command)) == nil)
    }

    @Test("a dead key or an input method's key needs the players' search field itself; other keys don't")
    func composing() throws {
        #expect(!StatusMenuController.composes(try Self.keyDown("a"), inputMethod: false))
        #expect(StatusMenuController.composes(try Self.keyDown("", ignoring: "´", code: 39), inputMethod: false)) // a dead key
        #expect(StatusMenuController.composes(try Self.keyDown("k"), inputMethod: true))
        #expect(!StatusMenuController.composes(try Self.keyDown("\u{F701}", code: 125), inputMethod: true))
    }

    @Test("one key mapping for the menu and Settings: plain arrows, Return or Enter, Space, Tab with or without Shift; others, or with ⌘ ⌥ ⌃ ⇧, are the window's")
    func highlightKeys() {
        #expect(HighlightKey(keyCode: 125, modifiers: []) == .down)
        #expect(HighlightKey(keyCode: 126, modifiers: [.numericPad, .function]) == .up) // arrows carry these
        #expect(HighlightKey(keyCode: 76, modifiers: []) == .returnKey)
        #expect(HighlightKey(keyCode: 49, modifiers: []) == .space)
        #expect(HighlightKey(keyCode: 48, modifiers: .shift) == .tab)
        #expect(HighlightKey(keyCode: 125, modifiers: .command) == nil)
        #expect(HighlightKey(keyCode: 124, modifiers: .shift) == nil)
        #expect(HighlightKey(keyCode: 48, modifiers: .control) == nil)
        #expect(HighlightKey(keyCode: 0, modifiers: []) == nil)
    }

    // MARK: - Opening and the keyboard

    /// A menu whose clock the test moves, its menu bar item at the top right.
    private func menuWithItem() -> (sut: StatusMenuController, clock: ManualClock, item: CGRect) {
        let sut = makeController()
        let clock = ManualClock(start: Date())
        sut.now = { clock.now }
        let item = CGRect(x: 1200, y: 870, width: 30, height: 24)
        sut.itemFrame = { item }
        return (sut, clock, item)
    }

    @Test("the click that closed the menu from outside, over its menu bar item, doesn't open it again as it reaches the item")
    func clickOnItemAfterClosing() {
        let (sut, clock, item) = menuWithItem()
        defer { sut.remove() }
        sut.open(showsPanel: false)
        sut.pointerLocation = { CGPoint(x: item.midX, y: item.midY) }
        sut.closeForClickElsewhere() // the click goes down over the item: it closes the menu first
        #expect(!sut.isMenuOpen)
        clock.advance(by: 0.2)
        sut.statusItemClicked() // the same click, reaching the item
        #expect(!sut.isMenuOpen)
    }

    @Test("a click on the menu bar item 0.4 s after one over it closed the menu from outside opens it")
    func laterClickOnItemOpens() {
        let (sut, clock, item) = menuWithItem()
        defer { sut.remove() }
        sut.open(showsPanel: false)
        sut.pointerLocation = { CGPoint(x: item.midX, y: item.midY) }
        sut.closeForClickElsewhere()
        clock.advance(by: 0.5)
        sut.statusItemClicked() // another click
        #expect(sut.isMenuOpen)
    }

    @Test("a click on the menu bar item just after a click elsewhere closed the menu opens it")
    func clickOnItemAfterClickElsewhere() {
        let (sut, clock, item) = menuWithItem()
        defer { sut.remove() }
        sut.open(showsPanel: false)
        sut.pointerLocation = { CGPoint(x: item.minX - 200, y: item.midY) }
        sut.closeForClickElsewhere() // elsewhere
        clock.advance(by: 0.1)
        sut.statusItemClicked()
        #expect(sut.isMenuOpen)
    }

    @Test("a key only the players' search can compose gives it the keyboard: the side window becomes key, its search the focus, and the key reaches it once")
    func searchTakesKeyboard() async throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.playerOptions = (1...PlayerOption.searchThreshold).map {
            PlayerOption(bundleID: "com.example.player\($0)", name: "Player \($0)", appURL: URL(fileURLWithPath: "/Applications/Player \($0).app"))
        }
        status.chosenPlayerID = status.playerOptions[0].bundleID
        sut.status = status
        // The key is sent again once the search has the focus, which SwiftUI gives it in its next update.
        // Another suite's window can take the key from this process's windows meanwhile, and SwiftUI drops
        // a focus asked for then: the side window is made key and the focus asked for again, as a next key would.
        sut.pause = { _ in
            await TestWait.until {
                await MainActor.run {
                    if let side = sut.sidePanel, !side.isKeyWindow {
                        side.makeKey()
                        sut.model.searchFocus += 1
                    }
                    return sut.sidePanel?.firstResponder is NSTextView
                }
            }
        }
        sut.open() // on screen
        sut.perform(.openSide(.players))
        let side = try #require(sut.sidePanel)
        #expect(side.isVisible && sut.model.players.showsSearch)
        let focus = sut.model.searchFocus
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                windowNumber: side.windowNumber, context: nil, characters: "a",
                                                charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        sut.searchTakesKeyboard(replaying: key)
        #expect(side.isKeyWindow)
        #expect(sut.model.searchFocus == focus + 1)
        await TestWait.until { sut.model.playerSearch == "a" } // typed once
    }

    @Test("the menu reads AntiDot mode live from the settings, so the players follow its switch in the menu at once")
    func antiDotModeLive() {
        let settingsModel = SettingsModel.forTests(actions: actions, updates: updates, settings: settings)
        let sut = makeController(settingsModel: settingsModel)
        defer { sut.remove() }
        sut.status = readyStatus()
        reopen(sut)
        #expect(!sut.model.isAntiDotMode)
        settings.setDetectionMethod(.playbackSignals)
        #expect(sut.model.isAntiDotMode) // without opening the menu again
        settings.setDetectionMethod(.audioLevels)
        #expect(!sut.model.isAntiDotMode)
    }

    @Test("a window shows less than its content only when the screen caps it: then the menu says more is below")
    func cappedByScreen() {
        #expect(StatusMenuController.isCapped(height: 600, content: 700))
        #expect(!StatusMenuController.isCapped(height: 700, content: 700.3))
        #expect(!StatusMenuController.isCapped(height: 700, content: 650))
    }

    @Test("a click on the menu bar item closes the open menu")
    func iconClosesMenu() {
        let sut = makeController()
        defer { sut.remove() }
        sut.open(showsPanel: false)
        sut.statusItemClicked()
        #expect(!sut.isMenuOpen)
    }
}
