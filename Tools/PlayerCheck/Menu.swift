import AppKit
import AutoHushKit
import MenuPlayers

// MARK: - Accessibility, as AutoHush reads it

// AutoHushKit's `value(_:)` and `children` read attributes, as AutoHush's players do.
extension AXUIElement {
    var actions: [String] {
        var names: CFArray?
        return AXUIElementCopyActionNames(self, &names) == .success ? names as? [String] ?? [] : []
    }
    var title: String { value(kAXTitleAttribute) as? String ?? "" }
    func text(_ attribute: String) -> String { value(attribute) as? String ?? "" }
    var frame: CGRect? {
        guard let position = value(kAXPositionAttribute), let size = value(kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
}

/// The windows last found on other desktops: the search takes about 70 ms
/// (up to 1 s), and pages are read every quarter second, so they're kept
/// for 10 s while each still answers as a window.
@MainActor var otherDesktopWindows: (pid: pid_t, windows: [AXUIElement], found: Date)?

/// The app's windows on this desktop, else on any other, as AutoHush finds
/// them (`AccessibilityWindows`: about 70 ms, 1 s at most); `onThisDesktop`
/// false: not on screen, so nothing there can be hit-tested.
@MainActor func appWindows(of pid: pid_t) -> (windows: [AXUIElement], onThisDesktop: Bool) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    let shown = app.elements(kAXWindowsAttribute)
    guard shown.isEmpty, AccessibilityWindows.isAvailable else { return (shown, true) }
    if let kept = otherDesktopWindows, kept.pid == pid, Date().timeIntervalSince(kept.found) < 10,
       !kept.windows.isEmpty, kept.windows.allSatisfy({ $0.text(kAXRoleAttribute) == kAXWindowRole }) {
        return (kept.windows, false)
    }
    let found = AccessibilityWindows.windows(ofProcess: pid) ?? []
    otherDesktopWindows = (pid, found, Date())
    return (found, false)
}

/// Whether what a window shows can be hit-tested: it's on this desktop, not
/// minimized, and its app isn't hidden.
func isOnScreen(_ window: AXUIElement, onThisDesktop: Bool, appHidden: Bool) -> Bool {
    onThisDesktop && !appHidden && window.value(kAXMinimizedAttribute) as? Bool != true
}

// MARK: - Playback menu (Accessibility, as AutoHush's AccessibilityPlaybackMenu)

struct FoundMenu {
    let title: String
    let toggle: AXUIElement
    /// Found as AutoHush finds it (⌘← and ⌘→); otherwise only by its arrows
    /// with other modifiers, which AutoHush doesn't look for.
    let asAutoHushFindsIt: Bool
    /// Its Previous and Next shortcuts, e.g. "⌘← ⌘→" or "⇧← ⇧→".
    let arrows: String
    var toggleTitle: String { toggle.title }
    var toggleEnabled: Bool { toggle.value(kAXEnabledAttribute) as? Bool ?? false }
}

/// The menu whose items include ⌘← and ⌘→ (Previous and Next), with Play or
/// Pause first: how AutoHush finds it whatever the app's language. Else one
/// whose first item is on Space and that has ← and → under other modifiers
/// (Deezer's Play menu: Space, ⇧← and ⇧→), which AutoHush finds too. Looked
/// up afresh each time, as some apps rebuild their menus on every change.
func playbackMenu(pid: pid_t) -> FoundMenu? {
    let app = AXUIElementCreateApplication(pid)
    // As AutoHush waits for a menu (`AccessibilityPlaybackMenu.timeout`).
    AXUIElementSetMessagingTimeout(app, AccessibilityPlaybackMenu.timeout)
    guard let bar = app.value(kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
    let menuBar = bar as! AXUIElement
    var other: FoundMenu?
    for barItem in menuBar.children {
        guard let menu = barItem.children.first, let first = menu.children.first else { continue }
        // Each arrow key's modifiers, every item's (AXMenuItemCmdModifiers: 0 is ⌘ alone):
        // TIDAL has ⌘← for Previous and ⇧⌘← for Seek back. An item that doesn't
        // say counts as ⌘ here, but AutoHush takes only one that says 0.
        var arrows: [Int: [Int]] = [:], saidCommand: Set<Int> = []
        for item in menu.children {
            if let key = item.value(kAXMenuItemCmdVirtualKeyAttribute) as? Int, key == 123 || key == 124 {
                let modifiers = item.value(kAXMenuItemCmdModifiersAttribute) as? Int
                arrows[key, default: []].append(modifiers ?? 0)
                if modifiers == 0 { saidCommand.insert(key) }
            }
        }
        guard let left = arrows[123], let right = arrows[124] else { continue }
        if left.contains(0), right.contains(0) {
            let asAutoHush = saidCommand == [123, 124]
            return FoundMenu(title: barItem.title, toggle: first, asAutoHushFindsIt: asAutoHush,
                             arrows: asAutoHush ? "⌘← ⌘→" : "← → (with no modifiers given)")
        }
        if other == nil, first.value(kAXMenuItemCmdVirtualKeyAttribute) as? Int == 49 {
            other = FoundMenu(title: barItem.title, toggle: first, asAutoHushFindsIt: true,
                              arrows: "\(modifierSymbols(left[0]))← \(modifierSymbols(right[0]))→")
        }
    }
    return other
}

/// The symbols of AXMenuItemCmdModifiers: ⇧ 1, ⌥ 2, ⌃ 4, and 8 for no ⌘.
func modifierSymbols(_ modifiers: Int) -> String {
    (modifiers & 4 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "") + (modifiers & 1 != 0 ? "⇧" : "")
        + (modifiers & 8 != 0 ? "" : "⌘")
}

/// The app's playback menu, as found when the check read it.
@MainActor var menu: FoundMenu?

/// Its Play/Pause item as it reads now: for a menu found as AutoHush finds
/// it, through AutoHush's own `AccessibilityPlaybackMenu`; else this tool's.
@MainActor func menuToggle(pid: pid_t) -> MenuToggle? {
    if menu?.asAutoHushFindsIt == true, let toggle = AccessibilityPlaybackMenu().toggle(pid: pid) { return toggle }
    return playbackMenu(pid: pid).map { MenuToggle(title: $0.toggleTitle, isEnabled: $0.toggleEnabled) }
}

/// Presses its Play/Pause item, as AutoHush presses it when it finds the
/// menu its way (`AccessibilityPlaybackMenu.pressToggle`).
@MainActor func pressMenuToggle(pid: pid_t) -> Bool {
    if menu?.asAutoHushFindsIt == true, AccessibilityPlaybackMenu().pressToggle(pid: pid) { return true }
    guard let item = playbackMenu(pid: pid)?.toggle else { return false }
    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
}

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
    say("Playback Menu")
    if !pressNeeds([.menu]) {
        say("  not read: --via \(via!.rawValue) doesn't need it")
    } else if running == nil {
        say("  not checked: the app isn't running")
    } else if !AXIsProcessTrusted() {
        say("  not checked: this tool (or the app running it) needs the Accessibility permission")
    } else if let found = playbackMenu(pid: running!.processIdentifier) {
        menu = found
        say("  “\(found.title)”: first item “\(found.toggleTitle)”, "
            + (found.toggleEnabled ? "enabled" : "disabled (nothing to play now, or nobody signed in)"))
        if found.arrows != "⌘← ⌘→" {
            say("  its Previous and Next are \(found.arrows), not ⌘← ⌘→"
                + (found.asAutoHushFindsIt ? ": AutoHush finds it by its first item, on Space" : ": AutoHush wouldn't find this menu as it is"))
        }
        say("  " + (ownAppWords.map { "its own words for Play and Pause, as AutoHush's menu players read them: \($0.words.play.count) and"
                                     + " \($0.words.pause.count), from \($0.source)" }
                    ?? "its own words for Play and Pause weren't found in its bundle: its item is read with this tool's list"))
    } else {
        say("  none: no menu with ⌘← and ⌘→, nor one with its first item on Space and other arrows")
    }
}
