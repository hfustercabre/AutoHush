import AppKit
import AutoHushKit
import WebAppPlayers

// MARK: - Page buttons (a web page in its windows, or a Flutter app's interface)

/// The switches for assistive tools: attributes set on an app to have it
/// show its interface to Accessibility. Electron's is documented
/// (electronjs.org, Accessibility); VoiceOver's is the one VoiceOver sets.
let manualAccessibility = "AXManualAccessibility"
let enhancedUserInterface = "AXEnhancedUserInterface"
func switchName(_ attribute: String, of interface: HiddenInterface? = hiddenInterface) -> String {
    if attribute == manualAccessibility { return "Electron's switch" }
    if case .chromiumWebApp(_, let browser)? = interface { return "\(browser)'s VoiceOver switch" }
    return "VoiceOver's switch"
}

/// An interface the app keeps out of Accessibility until an assistive tool
/// asks for it, by the framework in its bundle, with the switches that ask,
/// in the order they're tried:
/// - Electron: its own, `AXManualAccessibility`;
/// - Chromium Embedded Framework (CEF; Spotify): none of its own, as each
///   app decides: Electron's, else VoiceOver's `AXEnhancedUserInterface`,
///   which CEF's sample app listens to (Spotify takes only that one);
/// - Flutter (Spotube): VoiceOver's only (Flutter's engine listens for it);
/// - a Chromium browser's web app (Chrome's, Brave's): VoiceOver's, set on
///   the browser (`switchTarget`), whose own process serves the page shown
///   in the web app's window; Chromium turns its complete mode on for all
///   its windows and tabs 2 s later (chrome_browser_application_mac.mm).
/// Electron's, CEF's and a browser's web app's interface is a web page, as a
/// Safari web app's; Flutter's is the window's own elements. Any other app's
/// web page (as in a Tauri app, Safari's WebKit) shows as it is.
enum HiddenInterface {
    case electron(version: String), cef, flutter
    /// The web app's browser: its bundle ID and name.
    case chromiumWebApp(browserID: String, browser: String)
    var name: String {
        switch self {
        case .electron(let version): "Electron \(version)"
        case .cef: "Chromium (CEF)"
        case .flutter: "Flutter"
        case .chromiumWebApp(_, let browser): "\(browser) web app"
        }
    }
    var switches: [String] {
        switch self {
        case .electron: [manualAccessibility]
        case .cef: [manualAccessibility, enhancedUserInterface]
        case .flutter, .chromiumWebApp: [enhancedUserInterface]
        }
    }
    /// The app's, by the frameworks in its bundle; a Chromium browser's web
    /// app by its launcher's Info.plist, which names the site it opens and
    /// the browser it belongs to (Chromium writes both for every browser).
    static func of(_ appURL: URL) -> HiddenInterface? {
        let info = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        if info["CrAppModeShortcutURL"] != nil, let browserID = info["CrBundleIdentifier"] as? String {
            let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browserID).flatMap { Bundle(url: $0)?.infoDictionary }
                .flatMap { ($0["CFBundleDisplayName"] ?? $0["CFBundleName"]) as? String } ?? browserID
            return .chromiumWebApp(browserID: browserID, browser: browser)
        }
        let frameworks = appURL.appendingPathComponent("Contents/Frameworks")
        func framework(_ name: String) -> URL? {
            let url = frameworks.appendingPathComponent("\(name).framework")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let electron = framework("Electron Framework") {
            return .electron(version: Bundle(url: electron)?.infoDictionary?["CFBundleVersion"] as? String ?? "?")
        }
        if framework("Chromium Embedded Framework") != nil { return .cef }
        if framework("FlutterMacOS") != nil { return .flutter }
        return nil
    }
}
let hiddenInterface = HiddenInterface.of(appURL)
var isFlutter: Bool { if case .flutter? = hiddenInterface { true } else { false } }
var isElectron: Bool { if case .electron? = hiddenInterface { true } else { false } }
/// A Chromium browser's web app: its browser's name; nil for any other app.
var webAppBrowser: String? { if case .chromiumWebApp(_, let browser)? = hiddenInterface { browser } else { nil } }

/// The process a switch is set on: a Chromium browser's web app's browser
/// (its own process serves the page; set on the web app, nothing shows),
/// else the app itself. Its sound and keep-awake assertions are the
/// browser's too (`soundOwner`).
func switchTarget(_ pid: pid_t) -> pid_t {
    guard case .chromiumWebApp(let browserID, _)? = hiddenInterface,
          let browser = NSRunningApplication.runningApplications(withBundleIdentifier: browserID).first else { return pid }
    return browser.processIdentifier
}

/// Whether its page is Safari's WebKit: a Safari web app's, or the app's
/// own (a Tauri app's, as Pake's YouTube Music), and not Chromium inside Qt
/// (Qt WebEngine). Out of sight, WebKit keeps its words current: Pake's
/// YouTube Music and SoundCloud's web app, on another desktop, showed each
/// change within 0.5 s, also after minutes there.
let pageIsWebKit: Bool = {
    if isWebApp { return true }
    guard hiddenInterface == nil, let binary = Bundle(url: appURL)?.executableURL,
          linkedFrameworks(binary).contains("WebKit") else { return false }
    let frameworks = (try? FileManager.default.contentsOfDirectory(atPath: appURL.appendingPathComponent("Contents/Frameworks").path)) ?? []
    return !frameworks.contains { $0.hasPrefix("QtWebEngine") }
}()

/// A button of the app's page (a pressable item of a Flutter app's
/// interface), named by `label(of:)`.
struct FoundButton {
    let element: AXUIElement
    let label: String
    /// Points from its middle to its window's bottom; nil without a frame.
    let fromBottom: Double?
    /// Inside its window. One scrolled out of an Electron window is squeezed
    /// to no height at the window's edge (Deezer's song tiles), so it isn't.
    let inSight: Bool
    /// In a window on screen (`isOnScreen`), so it can be hit-tested.
    let onScreen: Bool
}

/// Roles never walked into looking for a page: a native app's long lists
/// (Music's songs) hold none.
let listRoles: Set<String> = [kAXTableRole, kAXOutlineRole, kAXBrowserRole, kAXListRole, "AXGrid", kAXTextAreaRole]

/// Walks an element's tree breadth first, reading at most `limit` elements
/// and going at most `maxDepth` levels down; `visit` says whether to go
/// into each one's children.
func walkTree(from root: AXUIElement, limit: Int, maxDepth: Int, _ visit: (AXUIElement, Int) -> Bool) {
    var queue: [(AXUIElement, Int)] = [(root, 0)], next = 0
    while next < queue.count, next < limit {
        let (element, depth) = queue[next]
        next += 1
        if visit(element, depth), depth < maxDepth { queue += element.children.map { ($0, depth + 1) } }
    }
}

/// The web pages (AXWebArea) in a window, as AutoHush's web app reader
/// finds them (up to 16 levels down), nearest first, reading at most 2,000
/// of its elements, so a native app's window isn't read whole.
func webAreas(in window: AXUIElement) -> [AXUIElement] {
    var found: [AXUIElement] = []
    walkTree(from: window, limit: 2000, maxDepth: 16) { element, _ in
        let role = element.text(kAXRoleAttribute)
        if role == "AXWebArea" {
            found.append(element)
            return false
        }
        return !listRoles.contains(role)
    }
    return found
}

/// A Flutter window's items that can be pressed (its buttons, and the texts
/// and images it marks pressable), reading at most 3,000 of its elements;
/// not the window's own close, minimize and full-screen buttons.
func pressableItems(in window: AXUIElement) -> [AXUIElement] {
    var found: [AXUIElement] = []
    walkTree(from: window, limit: 3000, maxDepth: 40) { element, depth in
        if depth == 1, element.text(kAXRoleAttribute) == kAXButtonRole { return false }
        if depth > 0, element.actions.contains(kAXPressAction) { found.append(element) }
        return true
    }
    return found
}

/// Whether one of the app's windows holds a web page.
@MainActor func hasWebPage(pid: pid_t) -> Bool {
    appWindows(of: pid).windows.contains { !webAreas(in: $0).isEmpty }
}

/// The buttons of the pages in the app's windows, found as AutoHush's web
/// app reader finds them (each window's AXWebArea on this desktop, else on
/// another, then AXUIElementsForSearchPredicate), or a Flutter app's
/// pressable items; nil when it has no window.
@MainActor func pageButtons(pid: pid_t) -> [FoundButton]? {
    let (windows, onThisDesktop) = appWindows(of: pid)
    guard !windows.isEmpty else { return nil }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    let hidden = app.value(kAXHiddenAttribute) as? Bool == true
    let search: [String: Any] = ["AXSearchKey": "AXButtonSearchKey", "AXResultsLimit": 2000, "AXDirection": "AXDirectionNext",
                                 "AXVisibleOnly": false, "AXImmediateDescendantsOnly": false]
    return windows.flatMap { window -> [FoundButton] in
        AXUIElementSetMessagingTimeout(window, 1)
        guard let windowFrame = window.frame else { return [] }
        let onScreen = isOnScreen(window, onThisDesktop: onThisDesktop, appHidden: hidden)
        let elements = isFlutter ? pressableItems(in: window) : webAreas(in: window).flatMap { area -> [AXUIElement] in
            var result: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(area, "AXUIElementsForSearchPredicate" as CFString,
                                                             search as CFDictionary, &result) == .success else { return [] }
            return result as? [AXUIElement] ?? []
        }
        return elements.map { element in
            AXUIElementSetMessagingTimeout(element, 0.5)
            let frame = element.frame
            return FoundButton(element: element, label: label(of: element),
                               fromBottom: frame.map { Double(windowFrame.maxY - $0.midY) },
                               inSight: frame.map { $0.width > 0 && $0.height > 0
                                   && (windowFrame.minY...windowFrame.maxY).contains($0.midY) } ?? false,
                               onScreen: onScreen)
        }
    }
}

/// The player's bar around the button: its nearest parent (three levels up
/// within the page, each read six deep, 500 elements at most) holding a
/// slider or a progress bar, as a player's bar has. Having one is what
/// AutoHush's learning weighs (`ButtonStanding.isWithPlayerControls`).
func playerBar(of element: AXUIElement) -> AXUIElement? {
    var reads = 500
    func holdsSlider(_ element: AXUIElement, depth: Int) -> Bool {
        guard reads > 0 else { return false }
        reads -= 1
        let role = element.text(kAXRoleAttribute)
        if role == kAXSliderRole || role == kAXProgressIndicatorRole { return true }
        return depth < 6 && element.children.contains { holdsSlider($0, depth: depth + 1) }
    }
    var node = element
    for _ in 0..<3 {
        guard let parent = node.value(kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
        node = parent as! AXUIElement
        if node.text(kAXRoleAttribute) == "AXWebArea" { return nil }
        if holdsSlider(node, depth: 0) { return node }
    }
    return nil
}

/// Whether nothing on its page sits over the button's middle: macOS's hit
/// test there (within the app) finds the button or something inside it.
/// Song tiles scrolled under a player bar (Deezer's, SoundCloud's) are in
/// the window, lower than the bar's own button, but covered. One hit test:
/// `playerButton` asks Chromium's approximate misses again.
func isUncovered(_ button: FoundButton, pid: pid_t) -> Bool {
    // Off screen (another desktop, hidden, minimized): whatever is there would answer.
    guard button.onScreen else { return true }
    guard let frame = button.element.frame else { return false }
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(pid), Float(frame.midX), Float(frame.midY), &hit) == .success,
          var node = hit else { return true } // can't tell: keep it
    for _ in 0..<8 {
        if CFEqual(node, button.element) { return true }
        guard let parent = node.value(kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
        node = parent as! AXUIElement
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
    // at first, then precisely a moment later (Spotify's bar button behind
    // other windows: a group elsewhere, then the button), so the misses are
    // asked again together, once, 0.2 s later: only when one of them could
    // change which button wins, being lower than the first uncovered one with
    // a player bar (Deezer's tiles under its bar can't).
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
/// Why the page wasn't checked, for the summary.
@MainActor var pageNotChecked: String?
/// The switch that showed the page; nil when it showed without one.
@MainActor var pageSwitch: String?
/// Whether the page was read: a press by the panel reads it only when its
/// row can't be told otherwise (`panelPress`).
@MainActor var pageRead = false
/// Set by a press when its page didn't show with the switch on: an
/// Electron, CEF or Flutter app builds it only while its window can be seen,
/// and a press doesn't bring it forward.
@MainActor var pageOutOfView = false

// MARK: - The switches for assistive tools

/// Turns a switch on; whether the app took it. One this tool turned on is
/// turned back off at the end, unless it may have been on before: VoiceOver's
/// reads back, so one already on is left alone; Electron's reads back off
/// even while it's on (Deezer), so with the page readable already (someone
/// may have it on) a check leaves it on, and a stop sets it back on. A press
/// always turns it off at the end: it leaves the app as it found it, and a
/// page kept for later goes stale out of sight (Deezer's took no presses
/// after minutes on another desktop).
@MainActor func turnOn(_ attribute: String, pid: pid_t, pageReadable: Bool) -> Bool {
    let app = AXUIElementCreateApplication(switchTarget(pid))
    AXUIElementSetMessagingTimeout(app, 1)
    if attribute == enhancedUserInterface, app.value(attribute) as? Bool == true {
        say("  \(switchName(attribute)) (\(attribute)) is on already: VoiceOver or another tool turned it on, so it's left on")
        changes.foundOn(attribute)
        return true
    }
    guard setSwitch(attribute, true, pid: pid) else {
        say("  \(switchName(attribute)) (\(attribute)): not taken")
        return false
    }
    if attribute == manualAccessibility, pageReadable, action == nil {
        say("  \(switchName(attribute)) on, and left on: VoiceOver or another tool may have it on")
        changes.foundOn(attribute)
    } else {
        changes.switchesOn.append(attribute)
    }
    return true
}

/// An Electron app takes presses on its page only in its fuller
/// accessibility mode, which starts 2 s after its switch last went on
/// (Electron debounces the requests; an off sent meanwhile cancels it, and
/// keeps a fuller mode already on: electron_application.mm). A press right
/// after the switch goes on does nothing, though the page shows and the
/// press is accepted. So before a press: at once when the switch reads back
/// on (Electron says so only in that mode), else not before those 2 s. A
/// Chromium browser's web app the same, the browser's complete mode 2 s
/// after its switch (chrome_browser_application_mac.mm); its switch reads
/// back on at once, so that tells nothing.
func waitForFullerMode(pid: pid_t) {
    let attribute: String
    switch hiddenInterface {
    case .electron?: attribute = manualAccessibility
    case .chromiumWebApp?: attribute = enhancedUserInterface
    default: return
    }
    guard let since = changes.switchSetOnAt(attribute) else { return }
    if isElectron {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard app.value(manualAccessibility) as? Bool != true else { return }
    }
    let wait = 2.2 - Date().timeIntervalSince(since)
    guard wait > 0 else { return }
    log(String(format: "  waited %.1f s for %@'s fuller mode: its page takes presses only 2 s after its switch goes on",
               wait, webAppBrowser ?? "Electron"))
    Thread.sleep(forTimeInterval: wait)
}

/// Turns on the app's `switches` in turn, each given 4 s for its page to
/// show: whether a page showed (in `count`, after `shownAfter` s), nil when
/// the app took none. A Chromium app builds its page only while its window
/// can be seen (Deezer's, covered: none), and once built it stays readable
/// covered, hidden or on another desktop; Spotify, on another desktop when
/// its switch went on, and Spotube, behind other windows, showed nothing
/// until the switch went on again in front. So when nothing shows, a check
/// brings the app forward a moment, once, turns on there again each switch
/// it took until one shows, then brings back the app that was in front. A
/// press never does (the tool should be as unintrusive as possible): it says
/// why the page can't be read, and the page way isn't used.
@MainActor func showPage(with switches: [String], pid: pid_t, count: inout Int, shownAfter: inout TimeInterval?) -> Bool? {
    /// Turns a switch this tool turned on back off.
    func off(_ attribute: String) {
        if changes.switchesOn.contains(attribute), setSwitch(attribute, false, pid: pid) {
            changes.switchesOn.removeAll { $0 == attribute }
        }
    }
    // The switches it took, and whether this tool turned each on (VoiceOver's
    // may have been on already: left as it is).
    var taken: [(attribute: String, ours: Bool)] = []
    var shown: (attribute: String, waited: (count: Int, after: TimeInterval))?
    for attribute in switches where shown == nil {
        guard turnOn(attribute, pid: pid, pageReadable: false) else { continue }
        taken.append((attribute, changes.switchesOn.contains(attribute)))
        let waited = waitForPage(pid, seconds: 4)
        if waited.count > 0 {
            shown = (attribute, waited)
        } else {
            say("  \(switchName(attribute)) (\(attribute)) on, but nothing showed in 4 s")
            off(attribute)
        }
    }
    guard !taken.isEmpty else { return nil }
    if shown == nil, action != nil { pageOutOfView = true }
    if shown == nil, action == nil {
        shown = inFront(pid: pid) {
            for (attribute, ours) in taken {
                if ours, !changes.switchesOn.contains(attribute), setSwitch(attribute, true, pid: pid) {
                    changes.switchesOn.append(attribute)
                }
                let waited = waitForPage(pid, seconds: 6)
                if waited.count > 0 { return (attribute, waited) }
                off(attribute)
            }
            return nil
        }
        say("  its window was out of sight: brought it forward a moment, with "
            + (taken.count == 1 ? "the switch" : "each switch") + " turned on again there"
            + " (Chromium and Flutter apps may build their \(isFlutter ? "interface" : "page") only while their window can be seen)"
            + (shown == nil ? "; nothing showed there either" : ""))
    }
    guard let (attribute, waited) = shown else { return false }
    count = waited.count
    shownAfter = waited.after
    pageSwitch = attribute
    return true
}

/// For a check: brings the app forward a moment for its page to be built,
/// runs `build` there, then brings back the app that was in front.
@MainActor func inFront<T>(pid: pid_t, _ build: () -> T) -> T {
    let front = NSWorkspace.shared.frontmostApplication
    if let front, front.processIdentifier != pid { changes.frontToRestore = front.bundleURL }
    bringForward(appURL)
    broughtForward = true
    let result = build()
    if let url = changes.frontToRestore {
        bringForward(url)
        changes.frontToRestore = nil
        // Its desktop slides away for about half a second, and the
        // frames read meanwhile are off (Spotify's Play: not in sight).
        Thread.sleep(forTimeInterval: 1)
    }
    return result
}

/// Whether the page shows a player's Play/Pause: a button in sight named
/// so, with a player's slider around it (no hit test: a quick look).
@MainActor func showsPlayerBar(_ pid: pid_t) -> Bool {
    (pageButtons(pid: pid) ?? []).contains { $0.inSight && named($0.label, playPauseWords) && playerBar(of: $0.element) != nil }
}

/// For a check that found the page readable already but with no player's
/// Play/Pause in it: the page may be a leftover, so it's built again.
/// Electron drops part of its page when its switch goes off, and doesn't
/// keep it up to date out of sight: a first check of Deezer, on another
/// desktop some ten minutes after a press had turned its switch off, found
/// no page button, and later checks did. The switch goes off and on, and the
/// player's bar is looked for up to 4 s; when it doesn't show, the app is
/// brought forward a moment, as `showPage` does (once per check), the switch
/// turned off and on there.
@MainActor func rebuildPage(with attribute: String, pid: pid_t) {
    func waitForBar(_ seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            Thread.sleep(forTimeInterval: 0.25)
            if showsPlayerBar(pid) { return true }
        } while Date() < deadline
        return false
    }
    func switchAgain() {
        _ = setSwitch(attribute, false, pid: pid)
        _ = setSwitch(attribute, true, pid: pid)
    }
    say("  no player's Play/Pause in it: it may be a leftover, so it's built again (\(switchName(attribute)) turned off and on)")
    let start = Date()
    switchAgain()
    if waitForBar(4) {
        say(String(format: "  its player bar showed after %.1f s", Date().timeIntervalSince(start)))
        return
    }
    let shown = inFront(pid: pid) {
        switchAgain()
        return waitForBar(6)
    }
    say("  not in place: brought it forward a moment, with the switch turned off and on there"
        + (shown ? String(format: "; its player bar showed (%.1f s in all)", Date().timeIntervalSince(start))
                 : "; still no player's Play/Pause"))
}

/// Why a press by the page didn't work, and what to try instead.
func pagePressHint() -> String {
    "; " + (webAppBrowser.map { "a \($0) web app" } ?? "an \(hiddenInterface.map { "app built with \($0.name)" } ?? "app")")
        + " may build its page, or take presses on it, only while its"
        + " window is in view: bring it into view and try again, or use another way (AppleScript, its menu, or the Now Playing panel"
        + " as a last resort)"
}

// MARK: - Reading the page

/// Reads the app's page: its buttons and its player's Play/Pause, turning on
/// the switch an Electron, CEF or Flutter app needs first. A press goes
/// straight to the player bar's button where it was last time, when it's
/// still there.
@MainActor func readPage() {
    pageRead = true
    pageNotChecked = nil
    guard let running else {
        say("  not checked: the app isn't running")
        pageNotChecked = "it isn't running"
        return
    }
    let pid = running.processIdentifier
    guard AXIsProcessTrusted() else {
        say("  not checked: this tool (or the app running it) needs the Accessibility permission")
        pageNotChecked = "no Accessibility permission"
        return
    }
    // A press: the player bar's button where it was last time.
    if pressingOneWay, useRememberedBar(pid: pid) { return }
    guard let before = pageButtons(pid: pid) else {
        // Deezer keeps playing with its window closed, and its page can't be
        // read then, not even through windows on other desktops.
        say("  not checked: no window open on any desktop; open it and run again (a closed window's page can't be read)")
        pageNotChecked = "no window open"
        return
    }
    if !isWebApp, hiddenInterface == nil, !hasWebPage(pid: pid) {
        say("  none: no web page in its windows, and not built with Electron, Chromium (CEF) or Flutter")
        pageNotChecked = "no page in its windows"
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
                                        + " (the Player Check app can relaunch it with it)"))
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
        pageSwitch = hidden.switches.first { turnOn($0, pid: pid, pageReadable: true) }
        readableAlready = true
    } else if count == 0, let hidden = hiddenInterface {
        if showPage(with: hidden.switches, pid: pid, count: &count, shownAfter: &shownAfter) == nil {
            pageNotChecked = "no switch was taken"
            return
        }
    } else if count == 0 {
        // A web page fills in once something first asks for it (YouTube
        // Music, just opened: 0 buttons at the first look, 36 a few
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
    if readableAlready, action == nil, let attribute = pageSwitch, !showsPlayerBar(pid) {
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
    let with = pageSwitch.map { "  \(switchName($0)) on: its " } ?? "  its "
    say((shownAfter.map { String(format: "%@%@ showed %d %@ after %.1f s", with, isFlutter ? "interface" : "page", buttons.count, items, $0) }
            ?? "\(with)\(isFlutter ? "interface" : "page"): \(buttons.count) \(items)")
        + String(format: " (one read, as AutoHush reads a web app: %.0f ms)", readTime * 1000))
    if let (button, withControls) = toggle {
        say(String(format: "  Play/Pause: “%@”, %.0f pt from the window's bottom, ", button.label, button.fromBottom ?? 0)
            + (withControls ? "with a player's slider around it" : "the lowest in sight (no slider around any)"))
    } else {
        let near = Set(buttons.map(\.label).filter { label in playPauseWords.contains { label.lowercased().contains($0) } })
        say("  none in sight named just Play or Pause" + (near.isEmpty ? "" : "; with those words: "
            + near.sorted().prefix(8).map { "“\($0)”" }.joined(separator: ", ")))
    }
}

/// The page's section of the report: read, unless a press by another way doesn't need it.
@MainActor func readPageButtons() {
    say()
    say("Page Buttons")
    if !pressNeeds([.page]) {
        say(via == .panel ? "  not read yet: a press by the panel reads it only when its windows' titles and current track don't tell its row"
                          : "  not read: --via \(via!.rawValue) doesn't need it")
        pageNotChecked = "not needed for --via \(via!.rawValue)"
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
/// lags a state (Deezer's said Pause while paused). In a test's window
/// state other than visible, never (a button's `onScreen` is from the read).
@MainActor func wordsCurrent(_ button: FoundButton) -> Bool {
    pageIsWebKit || (button.onScreen && (currentWindowState ?? .visible) == .visible)
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
        why = "its page's “\(button.label)” is disabled (sites disable it during ads): not pressed"
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
    // its words say what's wanted, or it toggles while a surer sign tells how it is.
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
