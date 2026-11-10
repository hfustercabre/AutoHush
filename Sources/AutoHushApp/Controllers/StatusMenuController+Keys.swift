import AppKit
import Carbon.HIToolbox

// StatusMenuController: the keys, as in macOS's menus.
extension StatusMenuController {
    /// The keys, as in macOS's menus, whatever the keyboard navigation
    /// setting (the user, 2026-10-18: "Arrows, as menus"), mapped as in
    /// Settings (`HighlightKey`): ↑ ↓ move the highlight through the menu's
    /// controls (`KeyHighlight`), or the side window's rows while it's open
    /// (the players' too: "Implement the same in the Media Player
    /// submenu"), row by row, Page Up and Page Down about a page, Home and
    /// End to the first and last (2026-11-01); Return or Space presses the one it's on; →
    /// opens a side window from its row, its first row lit, or lights it in
    /// one the pointer opened; ← closes it; on a slider or a choice, ← and →
    /// change it, and in a row of several (the durations, the buttons) they
    /// move along it. Among the players, typing goes to their search (Space
    /// too, once something is typed: before, it chooses, as in macOS's
    /// menus), and Return with nothing highlighted chooses the first one it
    /// left, only while something is typed. Keys with nothing to act on do nothing,
    /// without a beep, as in Settings. Tab and Shift-Tab go control by
    /// control, a row of several one after the other (B, 2026-11-09),
    /// staying in the open side window, as macOS keeps Tab in one window's
    /// loop (the user, 2026-11-10: "Do whatever macOS does"), the players'
    /// search one of the stops (`tab`). ↑ ↓ and Tab go on from a control
    /// that has the keyboard's focus (W9). With Option, Return and Space
    /// press as an Option-click does (`menuKey`).
    func handleKey(_ event: NSEvent) -> Bool {
        let key = Self.menuKey(event)
        // What the lit control does is what it shows, as the key is pressed.
        if key == .returnKey || key == .space { model.isOptionHeld = Self.optionAlone(event.modifierFlags) }
        // Space presses the highlighted player until something is typed.
        let spaceChooses = key == .space && model.playerSearch.isEmpty
        if model.isChoosingPlayer, model.players.showsSearch, !spaceChooses {
            if Self.composes(event) {
                // Only the field itself can compose it: it takes the keyboard.
                searchTakesKeyboard(replaying: event)
                return true
            }
            if let typed = Self.typedText(event) {
                // Typed into the players' search while the menu keeps the keyboard.
                perform(.searchPlayers(typed.isEmpty ? String(model.playerSearch.dropLast()) : model.playerSearch + typed))
                return true
            }
        }
        guard let key else { return false }
        return handle(key)
    }

    /// `event` as the menu's keys (`HighlightKey`), and Option-Return and
    /// Option-Space as Return and Space: they press the lit control as an
    /// Option-click does, Option showing what it does instead (Settings'
    /// button as Diagnostics, an added app's row as Remove; D1 and X1, the
    /// user's picks, 2026-11-10), as in macOS's menus, whose Option items
    /// Return chooses. Any other key with Option stays the panel's, and
    /// windows keep Option's keys to themselves.
    static func menuKey(_ event: NSEvent) -> HighlightKey? {
        if let key = HighlightKey(event) { return key }
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]) == .option,
              let key = HighlightKey(keyCode: event.keyCode, modifiers: []), key == .returnKey || key == .space else { return nil }
        return key
    }

    /// `key`, as `handleKey` takes it; `false` for Delete, which removes
    /// nothing in the menu.
    @discardableResult func handle(_ key: HighlightKey) -> Bool {
        let inSide = model.openSide != nil
        let keyboard = inSide ? model.sideKeyboard : model.keyboard
        switch key {
        case .up, .down:
            keyboard.move(key == .down ? 1 : -1)
            // One highlight at a time: the keyboard's focus, if a click gave it, goes, once moved on from.
            panel?.makeFirstResponder(nil)
        case .tab, .backTab:
            tab(key == .tab ? 1 : -1, in: keyboard)
            panel?.makeFirstResponder(nil)
        case .pageUp, .pageDown, .home, .end:
            panel?.makeFirstResponder(nil)
            if let jump = key.jump { keyboard.jump(jump) }
        case .returnKey where model.isChoosingPlayer:
            perform(.chooseHighlighted)
        case .returnKey, .space:
            keyboard.press()
        case .right:
            if !inSide, keyboard.highlightedOpensSide {
                // Into the side window, on its first row, as into a submenu
                // (once opened: opening clears its highlight).
                keyboard.press()
                model.sideKeyboard.highlightFirstWhenReady()
            } else if inSide, keyboard.highlighted == nil {
                keyboard.move(1) // one the pointer opened: its first row
            } else {
                _ = keyboard.adjust(1) || keyboard.moveInRow(1)
            }
        case .delete: // nothing in the menu is removed with it
            return false
        case .left:
            if inSide {
                closeSide()
            } else {
                _ = keyboard.adjust(-1) || keyboard.moveInRow(-1)
            }
        }
        return true
    }

    /// Tab (1) or Shift-Tab (-1) in `keyboard`'s window: the next control,
    /// or, past the last (the first) among the players, their search, which
    /// takes the keyboard, the highlight let go, as macOS's key loop goes
    /// into a field (K3, the user, 2026-11-10: "Into the field too");
    /// without one, round.
    private func tab(_ step: Int, in keyboard: KeyHighlight) {
        guard !keyboard.step(step, wraps: false) else { return }
        if keyboard === model.sideKeyboard, model.isChoosingPlayer, model.players.showsSearch, searchTakesKeyboard() {
            keyboard.clear()
        } else {
            keyboard.stepIn(step)
        }
    }

    /// A key while the players' search has the keyboard itself (`MenuPanel.onFieldKey`),
    /// before the field: Tab leaves it for the first player, Shift-Tab for
    /// the last stop, as macOS's key loop goes on from a field (K3), so
    /// macOS's focus never goes to its ✕ with the highlight shown besides
    /// (K4, 2026-11-10: one indicator at a time). The rest is the field's.
    func handleKeyInSearch(_ event: NSEvent) -> Bool {
        guard let key = HighlightKey(event), key == .tab || key == .backTab, model.isChoosingPlayer else { return false }
        searchGivesUpKeyboard()
        model.sideKeyboard.clear()
        model.sideKeyboard.stepIn(key == .tab ? 1 : -1)
        return true
    }

    /// What a key press types into a search: its characters, "" for Delete
    /// (one character back), `nil` for a key that doesn't type (arrows,
    /// Return, Escape, a shortcut with Command or Control).
    static func typedText(_ event: NSEvent) -> String? {
        guard event.modifierFlags.isDisjoint(with: [.command, .control]) else { return nil }
        if event.keyCode == 51 { return "" } // Delete
        guard let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 })
        else { return nil }
        return characters
    }

    /// Whether a key typed into the players' search needs the field itself:
    /// a dead key (é's ´, which waits for the next), or any typing key while
    /// an input method types (Japanese, Chinese…), which only a text field
    /// can compose.
    static func composes(_ event: NSEvent, inputMethod: Bool = typesThroughInputMethod) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control]) else { return false }
        let isDeadKey = event.characters?.isEmpty == true && event.charactersIgnoringModifiers?.isEmpty == false
        return isDeadKey || (inputMethod && typedText(event) != nil)
    }

    /// The keyboard's input source now is an input method, not a layout.
    static var typesThroughInputMethod: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let type = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return false }
        return Unmanaged<CFString>.fromOpaque(type).takeUnretainedValue() == kTISTypeKeyboardInputMode
    }
}
