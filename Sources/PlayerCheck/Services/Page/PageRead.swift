import AppKit
import CheckedPlayers
import PlayerCheckKit
import AutoHushKit

// MARK: - Reading the page

/// The page's Play/Pause in its player bar, found last, and the last full
/// search's answer while there's no bar (see `pageToggleLabel`).
@MainActor var barToggle: AXUIElement?
@MainActor var lastSearch = Date.distantPast
@MainActor var lastSearchLabel: String?

/// The page as read last (`readPage`).
@MainActor var page: PageCheck?
/// For an Electron app that runs: whether it was opened with the option its
/// page needs to take presses out of view (`LaunchOption`).
@MainActor var launchedWithOption: Bool? {
    guard isElectron, let running else { return nil }
    return ProcessArguments.of(running.processIdentifier).contains(LaunchOption.occludedWindows)
}

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

// MARK: - Its page's word

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
