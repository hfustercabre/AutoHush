import AppKit
import CheckedPlayers
import PlayerCheckKit
import AutoHushKit
import WebAppPlayers

// MARK: - Page buttons (a web page in its windows, or a Flutter app's interface)

/// The web pages (AXWebArea) in a window, as AutoHush's page reader finds
/// them (`AccessibilityWebPage.webAreas`): nearest first, at most 16 levels
/// down, reading at most 2,000 of its elements and none inside a list, so a
/// native app's window isn't read whole.
func webAreas(in window: AXUIElement) -> [AXUIElement] { AccessibilityWebPage.webAreas(in: window) }

/// Whether one of the app's windows holds a web page.
@MainActor func hasWebPage(pid: pid_t) -> Bool {
    appWindows(of: pid).windows.contains { !webAreas(in: $0).isEmpty }
}

/// The buttons of the pages in the app's windows (on this desktop, else on
/// another), or a Flutter app's pressable items, found as AutoHush's page
/// reader finds them (`AccessibilityWebPage.pageElements`), so a page way
/// that works here is one AutoHush can press; nil when it has no window.
@MainActor func pageButtons(pid: pid_t) -> [FoundButton]? {
    let (windows, onThisDesktop) = appWindows(of: pid)
    guard !windows.isEmpty else { return nil }
    let hidden = AXUIElement.application(pid, timeout: 1).value(kAXHiddenAttribute) as? Bool == true
    return windows.flatMap { window -> [FoundButton] in
        guard let windowFrame = window.frame else { return [] }
        let onScreen = isOnScreen(window, onThisDesktop: onThisDesktop, appHidden: hidden)
        // Each element waiting AutoHush's 0.5 s (`AccessibilityWebPage.timeout`).
        return AccessibilityWebPage.pageElements(in: window, access: pageAccess).map { element in
            let frame = element.frame
            return FoundButton(element: element, label: label(of: element),
                               fromBottom: frame.map { Double(windowFrame.maxY - $0.midY) },
                               inSight: frame.map { $0.width > 0 && $0.height > 0
                                   && (windowFrame.minY...windowFrame.maxY).contains($0.midY) } ?? false,
                               onScreen: onScreen)
        }
    }
}

/// The player's bar around the button, found as AutoHush's learning finds
/// it (`AccessibilityWebPage.playerBar(around:)`): its nearest parent (three
/// levels up within the page, each read six deep, 500 elements at most)
/// holding a slider or a progress bar, as a player's bar has. Having one is
/// what AutoHush's learning weighs (`ButtonStanding.isWithPlayerControls`).
func playerBar(of element: AXUIElement) -> AXUIElement? { AccessibilityWebPage.playerBar(around: element) }

/// Whether nothing on its page sits over the button's middle: macOS's hit
/// test there (within the app) finds the button or something inside it.
/// Song tiles scrolled under a player bar (an Electron app's, a web app's) are in
/// the window, lower than the bar's own button, but covered. One hit test:
/// `playerButton` asks Chromium's approximate misses again. The hit test
/// waits 1 s, as the app's other reads; what it finds and its parents, 0.5 s,
/// as the page's elements (`AccessibilityWebPage.timeout`).
func isUncovered(_ button: FoundButton, pid: pid_t) -> Bool {
    // Off screen (another desktop, hidden, minimized): whatever is there would answer.
    guard button.onScreen else { return true }
    guard let frame = button.element.frame else { return false }
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElement.application(pid, timeout: 1), Float(frame.midX), Float(frame.midY), &hit) == .success,
          var node = hit?.waiting(AccessibilityWebPage.timeout) else { return true } // can't tell: keep it
    for _ in 0..<8 {
        if CFEqual(node, button.element) { return true }
        guard let parent = node.element(kAXParentAttribute, timeout: AccessibilityWebPage.timeout) else { return false }
        node = parent
    }
    return false
}

/// The player's button named one of `words` (any case, alone or first),
/// ranked as AutoHush's learning ranks them: of those in sight and not
/// covered, the lowest with a player's slider or progress bar around it,
/// else the lowest (players keep their controls at the bottom).
@MainActor func playerButton(pid: pid_t, named words: Set<String>) -> (button: FoundButton, withControls: Bool)? {
    let candidates = (pageButtons(pid: pid) ?? [])
        .filter { $0.inSight && named($0.label, words) }
        .sorted { ($0.fromBottom ?? .infinity) < ($1.fromBottom ?? .infinity) }
    var bars: [Int: Bool] = [:]
    func hasBar(_ index: Int) -> Bool {
        if let known = bars[index] { return known }
        let found = playerBar(of: candidates[index].element) != nil
        bars[index] = found
        return found
    }
    // Each is hit-tested once. Chromium answers a hit test from its last one
    // at first, then precisely a moment later (a CEF app's bar button behind
    // other windows: a group elsewhere, then the button), so the misses are
    // asked again together, once, 0.2 s later: only when one of them could
    // change which button wins, being lower than the first uncovered one with
    // a player bar (song tiles under a bar can't).
    var open = candidates.map { isUncovered($0, pid: pid) }
    let firstBar = candidates.indices.first { open[$0] && hasBar($0) }
    if open.prefix(firstBar ?? candidates.count).contains(false) {
        Thread.sleep(forTimeInterval: 0.2)
        for index in candidates.indices where !open[index] { open[index] = isUncovered(candidates[index], pid: pid) }
    }
    var lowest: FoundButton?
    for index in candidates.indices where open[index] {
        if hasBar(index) { return (candidates[index], true) }
        if lowest == nil { lowest = candidates[index] }
    }
    return lowest.map { ($0, false) }
}

/// Waits up to `seconds` until the page's count of buttons holds for 0.75 s:
/// the count, and how long it took to settle.
@MainActor func waitForPage(_ pid: pid_t, seconds: Double) -> (count: Int, after: TimeInterval) {
    let start = Date()
    var count = 0, changed = start
    while Date().timeIntervalSince(start) < seconds, count == 0 || Date().timeIntervalSince(changed) < 0.75 {
        Thread.sleep(forTimeInterval: 0.25)
        let now = pageButtons(pid: pid)?.count ?? 0
        if now != count { count = now; changed = Date() }
    }
    return (count, changed.timeIntervalSince(start))
}
