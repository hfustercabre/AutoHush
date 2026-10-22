import AppKit
import Carbon.HIToolbox

// StatusMenuController: the keys, as in macOS's menus.
extension StatusMenuController {
    /// The keys, as in macOS's menus, whatever the keyboard navigation
    /// setting (the user, 2026-10-18: "Arrows, as menus"), mapped as in
    /// Settings (`HighlightKey`): ↑ ↓ move the highlight through the menu's
    /// controls (`KeyHighlight`), or the side window's rows while it's open
    /// (the players' too: "Implement the same in the Media Player
    /// submenu"), row by row; Return or Space presses the one it's on; →
    /// opens a side window from its row, its first row lit, or lights it in
    /// one the pointer opened; ← closes it; on a slider or a choice, ← and →
    /// change it, and in a row of several (the durations, the buttons) they
    /// move along it. Among the players, typing goes to their search (Space
    /// too, once something is typed: before, it chooses, as in macOS's
    /// menus), and Return with nothing highlighted chooses the first one it
    /// left, only while something is typed. Keys with nothing to act on do nothing,
    /// without a beep, as in Settings. Tab leaves the highlight to the
    /// keyboard's focus.
    func handleKey(_ event: NSEvent) -> Bool {
        // Space presses the highlighted player until something is typed.
        let spaceChooses = event.keyCode == 49 && model.playerSearch.isEmpty
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
        guard let key = HighlightKey(event) else { return false }
        return handle(key)
    }

    /// `key`, as `handleKey` takes it; `false` for Tab only, which goes on
    /// to the keyboard's focus.
    @discardableResult func handle(_ key: HighlightKey) -> Bool {
        let inSide = model.openSide != nil
        let keyboard = inSide ? model.sideKeyboard : model.keyboard
        switch key {
        case .tab: // the keyboard's focus takes over
            model.keyboard.clear()
            model.sideKeyboard.clear()
            return false
        case .up, .down:
            // One highlight at a time: the keyboard's focus, if Tab gave it, goes.
            panel?.makeFirstResponder(nil)
            keyboard.move(key == .down ? 1 : -1)
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
