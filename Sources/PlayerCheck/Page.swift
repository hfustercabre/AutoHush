import AppKit
import CheckedPlayers
import PlayerCheckKit
import AutoHushKit
import WebAppPlayers

// MARK: - Page buttons (a web page in its windows, or a Flutter app's interface)

/// A button of the app's page (a pressable item of a Flutter app's
/// interface), named by `label(of:)`, as AutoHush names it.
struct FoundButton {
    let element: AXUIElement
    let label: String
    /// Points from its middle to its window's bottom; nil without a frame.
    let fromBottom: Double?
    /// Inside its window. One scrolled out of an Electron window is squeezed
    /// to no height at the window's edge (an Electron player's song tiles), so it isn't.
    let inSight: Bool
    /// In a window on screen (`isOnScreen`), so it can be hit-tested.
    let onScreen: Bool
}

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

/// Set when the app had to be brought forward for its page to show.
@MainActor var broughtForward = false

/// The page's Play/Pause in its player bar, found last, and the last full
/// search's answer while there's no bar (see `pageToggleLabel`).
@MainActor var barToggle: AXUIElement?
@MainActor var lastSearch = Date.distantPast
@MainActor var lastSearchLabel: String?

/// What the page showed: how many buttons (0: none), and the player's
/// Play/Pause, with or without a player's slider around it (without, it's
/// likely a song's own button: nothing loaded, or nobody signed in).
struct PageCheck {
    let buttons: Int
    let toggle: FoundButton?
    var withControls = false
}

@MainActor var page: PageCheck?
/// For an Electron app that runs: whether it was opened with the option its
/// page needs to take presses out of view (`LaunchOption`).
@MainActor var launchedWithOption: Bool? {
    guard isElectron, let running else { return nil }
    return LaunchOption.arguments(of: running.processIdentifier).contains(LaunchOption.occludedWindows)
}
/// How the page was found.
@MainActor enum PageState {
    /// The switch that showed the page; nil when it showed without one.
    static var shownBySwitch: String?
    /// Whether the page was read: a press by the panel reads it only when
    /// its row can't be told otherwise (`panelPress`).
    static var read = false
    /// Set by a press when its page didn't show with the switch on: an
    /// Electron, CEF or Flutter app builds it only while its window can be
    /// seen, and a press doesn't bring it forward.
    static var outOfView = false
}

// MARK: - Reading the page

/// Reads the app's page: its buttons and its player's Play/Pause, turning on
/// the switch an Electron, CEF or Flutter app needs first. A press goes
/// straight to the player bar's button where it was last time, when it's
/// still there.
@MainActor func readPage() {
    PageState.read = true
    TestScope.pageNotChecked = nil
    guard let running else {
        say("  not checked: the app isn't running")
        TestScope.pageNotChecked = .notRunning
        return
    }
    let pid = running.processIdentifier
    guard AXIsProcessTrusted() else {
        say("  not checked: this tool (or the app running it) needs the Accessibility permission")
        TestScope.pageNotChecked = .noAccessibility
        return
    }
    // A press: the player bar's button where it was last time.
    if pressingOneWay, useRememberedBar(pid: pid) { return }
    guard let before = pageButtons(pid: pid) else {
        // An Electron player may keep playing with its window closed, and its page can't be
        // read then, not even through windows on other desktops.
        say("  not checked: no window open on any desktop; open it and run again (a closed window's page can't be read)")
        TestScope.pageNotChecked = .noWindowOpen
        return
    }
    if !isWebApp, hiddenInterface == nil, !hasWebPage(pid: pid) {
        say("  none: no web page in its windows, and not built with Electron, Chromium (CEF) or Flutter")
        TestScope.pageNotChecked = .noPage
        return
    }
    let items = isFlutter ? "pressable items" : "buttons"
    switch hiddenInterface {
    case .chromiumWebApp(_, let browser)?:
        say("  a \(browser) web app: its page shows, and takes presses, once \(switchName(enhancedUserInterface)) is on;"
            + " it's set on \(browser) itself, for all its windows and tabs")
    case let hidden?:
        say("  built with \(hidden.name): "
            + (isFlutter ? "its interface (not a web page) shows" : "its page shows")
            + " once a switch for assistive tools is on (" + hidden.switches.map { switchName($0) }.joined(separator: ", else ") + ")")
        if let launchedWithOption {
            say("  opened with \(LaunchOption.occludedWindows): "
                + (launchedWithOption ? "yes, so its page takes presses while its window is covered or on another desktop"
                                      : "no: its page takes no presses while its window is covered or on another desktop"
                                        + " (Add an App's Reopen, or the Player Check app's Relaunch, opens it with it)"))
        }
    case nil:
        say(isWebApp ? "  a Safari web app: WebKit shows its page as it is" : "  a web page in its windows: shown as it is")
    }
    var count = before.count
    var shownAfter: TimeInterval?
    var readableAlready = false
    if count > 0, let hidden = hiddenInterface {
        // Shown to an assistive tool before (VoiceOver, or this tool):
        // a switch still goes on, so the app keeps the page up to date.
        say("  readable already: an assistive tool asked for it before")
        PageState.shownBySwitch = hidden.switches.first { turnOn($0, pid: pid, pageReadable: true) }
        readableAlready = true
    } else if count == 0, let hidden = hiddenInterface {
        if showPage(with: hidden.switches, pid: pid, count: &count, shownAfter: &shownAfter) == nil {
            TestScope.pageNotChecked = .noSwitch
            return
        }
    } else if count == 0 {
        // A web page fills in once something first asks for it (a web
        // app, just opened: 0 buttons at the first look, 36 a few
        // seconds later).
        let waited = waitForPage(pid, seconds: 8)
        count = waited.count
        shownAfter = waited.after
        if count == 0 { say("  its page showed no buttons in 8 s: is the site loaded?") }
    }
    guard count > 0 else {
        if hiddenInterface != nil { say("  no switch showed it: its \(items) can't be read this way") }
        page = PageCheck(buttons: 0, toggle: nil)
        return
    }
    if readableAlready, action == nil, let attribute = PageState.shownBySwitch, !showsPlayerBar(pid) {
        rebuildPage(with: attribute, pid: pid)
    }
    let readStart = Date()
    let buttons = pageButtons(pid: pid) ?? []
    let readTime = Date().timeIntervalSince(readStart)
    let toggle = playerButton(pid: pid, named: playPauseWords)
    page = PageCheck(buttons: buttons.count, toggle: toggle?.button, withControls: toggle?.withControls ?? false)
    if let toggle, toggle.withControls {
        barToggle = toggle.button.element
        rememberPlace(of: toggle.button.element)
    }
    let with = PageState.shownBySwitch.map { "  \(switchName($0)) on: its " } ?? "  its "
    say((shownAfter.map { String(format: "%@%@ showed %d %@ after %.1f s", with, isFlutter ? "interface" : "page", buttons.count, items, $0) }
            ?? "\(with)\(isFlutter ? "interface" : "page"): \(buttons.count) \(items)")
        + String(format: " (one read, as AutoHush reads a web app: %.0f ms)", readTime * 1000))
    if let (button, withControls) = toggle {
        say(String(format: "  Play/Pause: %@, %.0f pt from the window's bottom, ", shown(button.label), button.fromBottom ?? 0)
            + (withControls ? "with a player's slider around it" : "the lowest in sight (no slider around any)"))
    } else {
        // Named by their words only: the rest is what they play (a playlist, an album).
        let near = Set(buttons.map(\.label).filter { label in playPauseWords.contains { label.lowercased().contains($0) } }.map(shown))
        say("  none in sight named just Play or Pause" + (near.isEmpty ? "" : "; with those words: "
            + near.sorted().prefix(8).joined(separator: ", ")))
    }
}

/// The page's section of the report: read, unless a press by another way doesn't need it.
@MainActor func readPageButtons() {
    say()
    say(CheckReportLine.Heading.page.rawValue)
    if !pressNeeds([.page]) {
        say(via == .panel ? "  not read yet: a press by the panel reads it only when its windows' titles and current track don't tell its row"
                          : "  not read: --via \(via!.rawValue) doesn't need it")
        TestScope.pageNotChecked = .notNeeded(via: via!)
    } else {
        readPage()
    }
}

// MARK: - Its page's word, and pressing it

/// The page's Play/Pause in its player bar, found last (`barToggle`): read
/// again by its words alone, as a full search reads the whole page and
/// hit-tests its buttons. A song's own button (no player bar around it)
/// isn't kept: a bar may show up once something plays. Without one, the
/// full search runs at most every 2 s.
@MainActor func pageToggleLabel(_ pid: pid_t) -> String? {
    if let element = barToggle {
        let words = label(of: element)
        if wordSays(words) != nil { return words }
        barToggle = nil // gone, or redrawn as another element
    }
    guard Date().timeIntervalSince(lastSearch) >= 2 else { return lastSearchLabel }
    let found = playerButton(pid: pid, named: playPauseWords)
    if let found, found.withControls {
        barToggle = found.button.element
        return found.button.label
    }
    lastSearch = Date()
    lastSearchLabel = found?.button.label
    return lastSearchLabel
}

/// Whether a page button's words are current: a WebKit page keeps them so
/// anywhere; a Chromium or Flutter page only while its window is on screen
/// (this desktop, not hidden or minimized): out of sight an Electron page
/// lags a state (one said Pause while paused). In a test's window
/// state other than visible, never (a button's `onScreen` is from the read).
@MainActor func wordsCurrent(_ button: FoundButton) -> Bool {
    pageIsWebKit || (button.onScreen && (WindowTest.currentState ?? .visible) == .visible)
}

/// Whether the page's Play/Pause word can be judged by now (`wordsCurrent`).
@MainActor var pageWordCurrent: Bool { page?.toggle.map(wordsCurrent) ?? false }

/// For a press, whether its page's player bar shows the app's state by its
/// button's word (`pageWordCurrent`). Then what it reports to Now Playing
/// isn't read (opening macOS's log and reading back to when the app opened:
/// 1.4–2 s). Out of sight, an Electron page's word is stale, so there the
/// log is read.
@MainActor var barShowsState: Bool {
    pressingOneWay && page?.withControls == true && pageWordCurrent
}

/// Presses a page button, as AutoHush's web apps press theirs: never one the
/// site disabled (during an ad, it can't be paused: AutoHush mutes the app
/// instead, which a one-off press can't hold); `why` says so.
@MainActor func pressPageButton(_ button: FoundButton, pausing: Bool, why: inout String?) -> Bool {
    if button.element.value(kAXEnabledAttribute) as? Bool == false {
        why = "its page's \(shown(button.label)) is disabled (sites disable it during ads): not pressed"
            + (pausing ? "; AutoHush would mute it instead" : "")
        return false
    }
    if let pid = running?.processIdentifier { waitForFullerMode(pid: pid) }
    return AXUIElementPerformAction(button.element, kAXPressAction as CFString) == .success
}

/// The page's button to press to pause (or play): the player bar's button
/// with that word; else, when the app's state is known (by script, else as
/// it reports to Now Playing), the bar's button whatever its word, since it
/// toggles (a Chromium page on another desktop keeps its word: Play while
/// it plays); else one with that word.
@MainActor func pageButtonToPress(pid: pid_t, pausing: Bool) -> FoundButton? {
    let wanted: PlayerState = pausing ? .playing : .paused // what its words say when it's the one to press
    // The button learned in this run, as AutoHush presses a web app's: when
    // its words say what's wanted, or it toggles while its scripted state or report tells how it is.
    if let learned {
        let words = label(of: learned.element)
        let says = learned.recipe.state(of: PageButton(handle: ButtonHandle(0), label: words))
        if says == wanted || (says != nil && (scriptedState() != nil || reportedState() != nil)) {
            return FoundButton(element: learned.element, label: words, fromBottom: nil, inSight: true, onScreen: page?.toggle?.onScreen ?? true)
        }
    }
    // A press takes the player bar's button the page section found (where
    // it was last time, or at its learned place), read again by its words
    // (no new search, no hit tests): when it says what's wanted, or toggles
    // while the app reports how it is.
    if pressingOneWay, page?.withControls == true, let bar = page?.toggle {
        let words = label(of: bar.element)
        let found = FoundButton(element: bar.element, label: words, fromBottom: bar.fromBottom, inSight: bar.inSight, onScreen: bar.onScreen)
        if wordSays(words) == wanted { return found }
        if !barShowsState, wordSays(words) != nil, scriptedState() != nil || reportedState() != nil { return found }
    }
    let named = playerButton(pid: pid, named: pausing ? pauseWords : playWords)
    if let named, named.withControls { return named.button }
    if scriptedState() != nil || reportedState() != nil, let bar = playerButton(pid: pid, named: playPauseWords), bar.withControls {
        return bar.button
    }
    return named?.button
}
