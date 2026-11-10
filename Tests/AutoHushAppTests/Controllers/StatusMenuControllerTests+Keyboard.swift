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

    @Test("closing the players with ← brings the keys' highlight back to the menu's row, so VoiceOver's cursor goes there, not to the card's text (VO1)")
    func closingReturnsToTheRow() throws {
        let sut = menuWithTwoPlayers()
        defer { sut.remove() }
        // The card's Change Player row, as its view registers it, lit by the keys.
        let row = UUID()
        sut.model.keyboard.register(row, .init(frame: CGRect(x: 0, y: 0, width: 300, height: 30),
                                               press: { sut.perform(.openSide(.players)) }))
        sut.model.keyboard.move(1)
        let lit = try #require(sut.model.keyboard.highlighted)
        #expect(sut.model.keyboard.isLitByKeys)
        let before = sut.model.keyboard.light(lit).arrivals
        sut.perform(.openSide(.players))
        #expect(sut.handleKey(MenuPanelTests.key(123))) // ←
        #expect(!sut.model.isChoosingPlayer)
        #expect(sut.model.keyboard.highlighted == lit)
        #expect(sut.model.keyboard.light(lit).arrivals == before + 1) // arrived again: VoiceOver and Zoom follow
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

    @Test("among the players, End and Home go to the last and first row, Page Down and Up a page on and back; the menu's highlight stays put")
    func jumpsThroughPlayers() {
        let sut = menuWithTwoPlayers()
        defer { sut.remove() }
        let (first, second) = twoPlayerRows(sut)
        #expect(sut.handleKey(MenuPanelTests.key(119))) // End
        #expect(sut.model.sideKeyboard.highlighted == second)
        #expect(sut.handleKey(MenuPanelTests.key(115))) // Home
        #expect(sut.model.sideKeyboard.highlighted == first)
        #expect(sut.handleKey(MenuPanelTests.key(121))) // Page Down: both show, the last
        #expect(sut.model.sideKeyboard.highlighted == second)
        #expect(sut.handleKey(MenuPanelTests.key(116))) // Page Up
        #expect(sut.model.sideKeyboard.highlighted == first)
        #expect(sut.model.keyboard.highlighted == nil)
        #expect(sut.model.isChoosingPlayer) // nothing chosen by them
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

    @Test("among the players, the search's ✕ (as its view registers it) is Tab's first stop, and Return on it empties the search; ↓ goes past it to the first player, as before (R3)")
    func searchClearByTab() {
        let sut = menuWithTwoPlayers()
        defer { sut.remove() }
        let (first, _) = twoPlayerRows(sut)
        sut.perform(.searchPlayers("Fi"))
        let clear = UUID()
        sut.model.sideKeyboard.register(clear, .init(frame: CGRect(x: 250, y: -30, width: 24, height: 24),
                                                     press: { sut.perform(.searchPlayers("")) }, tabOnly: true))
        #expect(sut.handleKey(MenuPanelTests.key(125))) // ↓: the first player, past the ✕
        #expect(sut.model.sideKeyboard.highlighted == first)
        #expect(sut.handleKey(MenuPanelTests.key(48, flags: .shift))) // Shift-Tab: the ✕
        #expect(sut.model.sideKeyboard.highlighted == clear)
        #expect(sut.handleKey(MenuPanelTests.key(36))) // Return: the search emptied, no player chosen
        #expect(sut.model.playerSearch.isEmpty && sut.model.isChoosingPlayer)
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

    @Test("in the menu, Tab goes to the next control and Shift-Tab to the one before; a menu opens with nothing highlighted")
    func tabStepsThroughControls() {
        let (sut, _, slider, sideRow) = menuWithRows()
        defer { sut.remove() }
        let keyboard = sut.model.keyboard
        let beside = UUID() // in the side row's row, to its right: ↓ and ↑ never stop on it
        keyboard.register(beside, .init(frame: CGRect(x: 310, y: 40, width: 40, height: 20), press: {}))
        #expect(sut.handleKey(MenuPanelTests.key(48))) // Tab: the first control
        #expect(keyboard.highlighted == slider)
        #expect(sut.handleKey(MenuPanelTests.key(48)))
        #expect(keyboard.highlighted == sideRow)
        #expect(sut.handleKey(MenuPanelTests.key(48))) // along the row
        #expect(keyboard.highlighted == beside)
        #expect(sut.handleKey(MenuPanelTests.key(48))) // wraps
        #expect(keyboard.highlighted == slider)
        #expect(sut.handleKey(MenuPanelTests.key(48, flags: .shift))) // Shift-Tab: back
        #expect(keyboard.highlighted == beside)
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

    @Test("one key mapping for the menu and Settings: plain arrows, Page Up and Down, Home and End, Return or Enter, Space, Tab and Shift-Tab; others, or with ⌘ ⌥ ⌃ ⇧, are the window's")
    func highlightKeys() {
        #expect(HighlightKey(keyCode: 125, modifiers: []) == .down)
        // fn with the arrows on a laptop: the same key codes, with fn.
        #expect(HighlightKey(keyCode: 116, modifiers: .function) == .pageUp)
        #expect(HighlightKey(keyCode: 121, modifiers: .function) == .pageDown)
        #expect(HighlightKey(keyCode: 115, modifiers: .function) == .home)
        #expect(HighlightKey(keyCode: 119, modifiers: []) == .end)
        #expect(HighlightKey(keyCode: 119, modifiers: .shift) == nil)
        #expect(HighlightKey.pageUp.jump == .pageUp && HighlightKey.pageDown.jump == .pageDown)
        #expect(HighlightKey.home.jump == .first && HighlightKey.end.jump == .last && HighlightKey.down.jump == nil)
        #expect(HighlightKey(keyCode: 126, modifiers: [.numericPad, .function]) == .up) // arrows carry these
        #expect(HighlightKey(keyCode: 76, modifiers: []) == .returnKey)
        #expect(HighlightKey(keyCode: 49, modifiers: []) == .space)
        #expect(HighlightKey(keyCode: 48, modifiers: []) == .tab)
        #expect(HighlightKey(keyCode: 48, modifiers: .shift) == .backTab)
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

    @Test("↓ while macOS's keyboard is on the menu bar item (it reaches AutoHush with no window, another app active) opens the menu; not with a window, with AutoHush active, another key or ⌘, nor while it's open (K6)")
    func downOnMenuBarItemOpens() {
        #expect(StatusMenuController.opensFromMenuBar(125, flags: [.function, .numericPad], hasWindow: false, appIsActive: false))
        #expect(!StatusMenuController.opensFromMenuBar(125, flags: [], hasWindow: true, appIsActive: false))
        #expect(!StatusMenuController.opensFromMenuBar(125, flags: [], hasWindow: false, appIsActive: true))
        #expect(!StatusMenuController.opensFromMenuBar(126, flags: [], hasWindow: false, appIsActive: false))
        #expect(!StatusMenuController.opensFromMenuBar(125, flags: .command, hasWindow: false, appIsActive: false))
        let sut = makeController()
        defer { sut.remove() }
        #expect(!sut.isMenuOpen)
        #expect(!sut.menuBarKey(125, flags: [], hasWindow: true, appIsActive: false))
        #expect(!sut.isMenuOpen)
        #expect(sut.menuBarKey(125, flags: [], hasWindow: false, appIsActive: false))
        #expect(sut.isMenuOpen)
        #expect(!sut.menuBarKey(125, flags: [], hasWindow: false, appIsActive: false)) // open already: the menu's own ↓
    }

    @Test("in a side window, Tab and Shift-Tab stay in it, wrapping round its rows, as macOS keeps Tab in one window (K2); the menu's highlight stays put")
    func tabStaysInSideWindow() {
        let (sut, _, _, sideRow) = menuWithRows()
        defer { sut.remove() }
        #expect(sut.handleKey(MenuPanelTests.key(125)) && sut.handleKey(MenuPanelTests.key(125)))
        #expect(sut.model.keyboard.highlighted == sideRow)
        sut.perform(.openSide(.ignoredApps))
        let appRow = UUID(), addRow = UUID()
        sut.model.sideKeyboard.register(appRow, .init(frame: CGRect(x: 0, y: 0, width: 280, height: 30), press: {}))
        sut.model.sideKeyboard.register(addRow, .init(frame: CGRect(x: 0, y: 40, width: 280, height: 30), press: {}))
        var seen: [UUID?] = []
        for _ in 0..<3 {
            #expect(sut.handleKey(MenuPanelTests.key(48)))
            seen.append(sut.model.sideKeyboard.highlighted)
        }
        #expect(seen == [appRow, addRow, appRow])
        #expect(sut.handleKey(MenuPanelTests.key(48, flags: .shift)))
        #expect(sut.model.sideKeyboard.highlighted == addRow)
        #expect(sut.model.keyboard.highlighted == sideRow && sut.model.openSide == .ignoredApps)
    }

    @Test("among the players, Shift-Tab before the first row (or Tab past the last) goes into their search, which takes the keyboard, the highlight let go; Tab out of it lights the first row, Shift-Tab the last, and ↓ stays the field's (K3, K4)")
    func tabIntoPlayersSearch() async throws {
        let sut = makeController()
        defer { sut.remove() }
        var status = readyStatus()
        status.playerOptions = (1...PlayerOption.searchThreshold).map {
            PlayerOption(bundleID: "com.example.player\($0)", name: "Player \($0)", appURL: URL(fileURLWithPath: "/Applications/Player \($0).app"))
        }
        status.chosenPlayerID = status.playerOptions[0].bundleID
        sut.status = status
        sut.open() // on screen: its rows register themselves
        sut.perform(.openSide(.players))
        let side = try #require(sut.sidePanel)
        #expect(side.isVisible && sut.model.players.showsSearch)
        let keyboard = sut.model.sideKeyboard
        await TestWait.until { keyboard.rows.count > 1 && !keyboard.controls.values.contains { $0.frame == .zero } }
        let order = keyboard.rows.flatMap { $0 }
        let first = try #require(order.first), last = try #require(order.last)
        let focus = sut.model.searchFocus
        #expect(sut.handleKey(MenuPanelTests.key(48))) // Tab: the first row
        #expect(keyboard.highlighted == first)
        #expect(sut.handleKey(MenuPanelTests.key(48, flags: .shift))) // before the first: the search
        #expect(sut.model.searchFocus == focus + 1 && keyboard.highlighted == nil)
        #expect(sut.handleKeyInSearch(MenuPanelTests.key(48))) // out of it: the first row
        #expect(keyboard.highlighted == first)
        #expect(sut.handleKeyInSearch(MenuPanelTests.key(48, flags: .shift))) // the last
        #expect(keyboard.highlighted == last)
        #expect(sut.handleKey(MenuPanelTests.key(48))) // past the last: the search again
        #expect(sut.model.searchFocus == focus + 2 && keyboard.highlighted == nil)
        #expect(!sut.handleKeyInSearch(MenuPanelTests.key(125))) // ↓: the field's own
        #expect(sut.model.keyboard.highlighted == nil)
    }

    @Test("Option counts as held only alone (with Shift too), not with VoiceOver's Control-Option nor with Command (F2)")
    func optionAlone() {
        #expect(StatusMenuController.optionAlone(.option))
        #expect(StatusMenuController.optionAlone([.option, .shift]))
        #expect(!StatusMenuController.optionAlone([.option, .control]))
        #expect(!StatusMenuController.optionAlone([.option, .command]))
        #expect(!StatusMenuController.optionAlone([]))
    }

    @Test("while Option is held, the toolbar's Settings button shows as Diagnostics, by its name and its symbol in Settings' sidebar, and opens it (D1)")
    func settingsButtonWithOption() {
        let plain = MenuToolbarView.settingsButton(optionHeld: false), held = MenuToolbarView.settingsButton(optionHeld: true)
        #expect(plain.title == MenuToolbarView.settingsTitle && plain.symbol == "gearshape" && plain.command == .openSettings)
        #expect(held.title == SettingsPage.diagnostics.title && held.symbol == SettingsPage.diagnostics.symbol)
        #expect(held.command == .showDiagnostics)
    }

    @Test("Option-Return or Option-Space on the toolbar's Settings button, lit by the keys, opens Diagnostics, as an Option-click; with Option, no other key is the menu's (D1)")
    func optionReturnOpensDiagnostics() async throws {
        for space in [false, true] {
            let sut = makeController()
            defer { sut.remove() }
            sut.status = readyStatus()
            sut.open() // on screen: its controls register themselves
            let keyboard = sut.model.keyboard
            await TestWait.until { keyboard.rows.count > 1 && !keyboard.controls.values.contains { $0.frame == .zero } }
            #expect(!sut.handleKey(MenuPanelTests.key(125, flags: .option))) // Option-↓
            #expect(!sut.handleKey(MenuPanelTests.key(48, flags: .option))) // Option-Tab
            #expect(keyboard.highlighted == nil)
            let settingsButton = try #require(keyboard.rows.last?.first) // the toolbar's first
            keyboard.highlight(settingsButton)
            sut.model.isOptionHeld = true // as the flags' monitor sets it
            #expect(sut.handleKey(MenuPanelTests.key(space ? 49 : 36, flags: .option, characters: space ? "\u{A0}" : "\r")))
            await TestWait.until { log.calls.contains("diagnostics") }
            #expect(!log.calls.contains("settings"))
            log.calls.removeAll()
        }
    }

    @Test("among the players, Option-Return or Option-Space on an added app's row, lit by the keys, removes it after asking, as an Option-click; the highlight stays on the row as Option goes down and up (X1)")
    func optionReturnRemovesAddedApp() async throws {
        for space in [false, true] {
            let sut = makeController()
            defer { sut.remove() }
            var status = readyStatus()
            status.playerOptions = [
                Self.first,
                PlayerOption(bundleID: "com.example.checked", name: "Checked", appURL: URL(fileURLWithPath: "/Applications/Checked.app"),
                             kind: .checkedApp),
            ]
            status.chosenPlayerID = TestPlayers.first
            sut.status = status
            sut.open() // on screen: its rows register themselves
            sut.perform(.openSide(.players))
            let keyboard = sut.model.sideKeyboard
            // First, Checked, Add an App…, Add a Web App…
            await TestWait.until { keyboard.rows.count == 4 && !keyboard.controls.values.contains { $0.frame == .zero } }
            let checked = keyboard.rows[1][0]
            keyboard.highlight(checked)
            for held in [true, false, true] { // Option down, up and down again: the row redrawn, still lit
                sut.model.isOptionHeld = held
                await Task.yield()
                await TestWait.until { keyboard.rows.count == 4 }
                #expect(keyboard.highlighted == checked)
            }
            #expect(sut.handleKey(MenuPanelTests.key(space ? 49 : 36, flags: .option, characters: space ? "\u{A0}" : "\r")))
            await TestWait.until { log.calls.contains("remove com.example.checked") }
            #expect(!log.calls.contains("player com.example.checked"))
            log.calls.removeAll()
        }
    }
}
