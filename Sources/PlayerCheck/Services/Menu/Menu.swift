import AppKit
import CheckedPlayers
import PlayerCheckKit
import AutoHushKit
import MenuPlayers
import WebAppPlayers

// MARK: - Playback menu (Accessibility, as AutoHush's AccessibilityPlaybackMenu)

/// The app's playback menu, found as AutoHush finds it, whatever the app's
/// language (`AccessibilityPlaybackMenu.playbackMenu`): the menu whose items
/// include ⌘← and ⌘→ (Previous and Next), with Play or Pause first; else one
/// whose first item is on Space and that has ← and → under other modifiers
/// (an Electron player's Play menu: Space, ⇧← and ⇧→). So a menu that works in the check
/// is one AutoHush presses. Looked up afresh each time, as some apps rebuild
/// their menus on every change.
func playbackMenu(pid: pid_t) -> FoundMenu? {
    guard let menuBar = menuBar(of: pid), let (barItem, toggle) = AccessibilityPlaybackMenu.playbackMenu(in: menuBar) else { return nil }
    return FoundMenu(title: barItem.title, toggle: toggle, arrows: arrows(in: barItem) ?? FoundMenu.standardArrows)
}

/// The app's menu bar, read as AutoHush waits for a menu (`AccessibilityPlaybackMenu.menuBar`).
func menuBar(of pid: pid_t) -> AXUIElement? { AccessibilityPlaybackMenu.menuBar(of: pid) }

/// A menu's Previous and Next shortcuts as they read ("⌘← ⌘→", "⇧← ⇧→"):
/// each arrow's with ⌘ alone when it has one, else its first; "with no
/// modifiers given" when one doesn't say; `nil` without both arrows.
func arrows(in barItem: AXUIElement) -> String? {
    var modifiers: [Int: [Int?]] = [:]
    let timeout = AccessibilityPlaybackMenu.timeout
    for item in barItem.children(timeout: timeout).first?.children(timeout: timeout) ?? [] {
        guard let key = item.value(kAXMenuItemCmdVirtualKeyAttribute) as? Int, AccessibilityPlaybackMenu.arrows.contains(key) else { continue }
        modifiers[key, default: []].append(item.value(kAXMenuItemCmdModifiersAttribute) as? Int)
    }
    guard let lefts = modifiers[123], let rights = modifiers[124] else { return nil }
    func pick(_ all: [Int?]) -> Int? { all.contains(0) ? 0 : all.compactMap { $0 }.first }
    guard let left = pick(lefts), let right = pick(rights) else { return "← → (with no modifiers given)" }
    return "\(modifierSymbols(left))← \(modifierSymbols(right))→"
}

/// A menu AutoHush doesn't find (`playbackMenu` found none): one whose ←
/// and → don't say their modifiers, which only a looser look finds. Said in
/// the report, never tried: AutoHush couldn't press it.
func unfoundMenu(pid: pid_t) -> (title: String, arrows: String)? {
    guard let menuBar = menuBar(of: pid) else { return nil }
    for barItem in menuBar.children(timeout: AccessibilityPlaybackMenu.timeout) {
        if let arrows = arrows(in: barItem), arrows.contains("no modifiers") { return (barItem.title, arrows) }
    }
    return nil
}

/// The symbols of AXMenuItemCmdModifiers: ⇧ 1, ⌥ 2, ⌃ 4, and 8 for no ⌘.
func modifierSymbols(_ modifiers: Int) -> String {
    (modifiers & 4 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "") + (modifiers & 1 != 0 ? "⇧" : "")
        + (modifiers & 8 != 0 ? "" : "⌘")
}

/// The app's playback menu, as found when the check read it.
@MainActor var menu: FoundMenu?

/// Its Play/Pause item as it reads now, through AutoHush's own `AccessibilityPlaybackMenu`.
@MainActor func menuToggle(pid: pid_t) -> MenuToggle? { AccessibilityPlaybackMenu().toggle(pid: pid) }

/// Presses its Play/Pause item, as AutoHush presses it (`AccessibilityPlaybackMenu.pressToggle`).
@MainActor func pressMenuToggle(pid: pid_t) -> Bool { AccessibilityPlaybackMenu().pressToggle(pid: pid) }

/// What its menu's Play/Pause item says of the state, as AutoHush's
/// MenuPlayer reads it: disabled, it's stopped (nothing to play); else by
/// the app's own words (`MenuPlayer.state(of:words:)`), else by this tool's
/// list ("Pause" while it plays). Nil when the item says neither.
@MainActor func menuState(_ toggle: MenuToggle) -> PlayerState? {
    guard toggle.isEnabled else { return .stopped }
    if let ownWords {
        let state = MenuPlayer.state(of: toggle, words: ownWords)
        if state != .unknown { return state }
    }
    let title = toggle.title.lowercased()
    return pauseWords.contains(title) ? .playing : playWords.contains(title) ? .paused : nil
}

@MainActor func reportMenu() {
    say()
    say(CheckReportLine.Heading.menu.rawValue)
    if !pressNeeds([.menu]) {
        say("  not read: --via \(via!.rawValue) doesn't need it")
    } else if running == nil {
        say("  not checked: the app isn't running")
    } else if !AXIsProcessTrusted() {
        say("  not checked: this tool (or the app running it) needs the Accessibility permission")
    } else if let found = playbackMenu(pid: running!.processIdentifier) {
        menu = found
        say("  “\(found.title)”: first item \(shown(found.toggleTitle)), "
            + (found.toggleEnabled ? "enabled" : "disabled (nothing to play now, or nobody signed in)"))
        if found.arrows != FoundMenu.standardArrows {
            say("  its Previous and Next are \(found.arrows), not \(FoundMenu.standardArrows): AutoHush finds it by its first item, on Space")
        }
        say("  " + (ownAppWords.map { "its own words for Play and Pause, as AutoHush's menu players read them: \($0.words.play.count) and"
                                     + " \($0.words.pause.count), from \($0.source)" }
                    ?? "its own words for Play and Pause weren't found in its bundle: its item is read with this tool's list"))
    } else if let unfound = unfoundMenu(pid: running!.processIdentifier) {
        say("  “\(unfound.title)” has Previous and Next as \(unfound.arrows): AutoHush wouldn't find this menu as it is,"
            + " so it isn't tried")
    } else {
        say("  none: no menu with ⌘← and ⌘→, nor one with its first item on Space and other arrows")
    }
}
