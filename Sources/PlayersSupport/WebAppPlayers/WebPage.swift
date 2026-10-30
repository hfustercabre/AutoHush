import AppKit
import ApplicationServices
import os
import AutoHushKit

/// One of a page's buttons, the same between looks while the page isn't
/// reloaded. Holds the button's Accessibility element; a number in tests.
package struct ButtonHandle: Hashable, @unchecked Sendable {
    let element: AnyHashable

    package init(_ element: AnyHashable) {
        self.element = element
    }
}

/// A button as one look at a page found it.
package struct PageButton: Equatable, Sendable {
    package let handle: ButtonHandle
    /// What it says to VoiceOver, e.g. "Pause" or "Play Discover Weekly", in
    /// the site's language.
    package let label: String
    let isEnabled: Bool

    package init(handle: ButtonHandle, label: String, isEnabled: Bool = true) {
        self.handle = handle
        self.label = label
        self.isEnabled = isEnabled
    }
}

/// What learning weighs about a button whose words changed, besides its
/// place. A player's bar is in sight, among the player's other controls; a
/// song's own button (a tile, a row) can be scrolled out of sight and has
/// none around it (measured on SoundCloud and YouTube Music).
package struct ButtonStanding: Equatable, Sendable {
    /// Inside its window: not scrolled below or above it.
    let isInWindow: Bool
    /// Something just around it holds a slider or a progress bar, as a
    /// player's bar does (its progress, its volume).
    package let isWithPlayerControls: Bool

    init(isInWindow: Bool = true, isWithPlayerControls: Bool = false) {
        self.isInWindow = isInWindow
        self.isWithPlayerControls = isWithPlayerControls
    }
}

/// Where a button is on its page, to find it again after a reload, when
/// every element is new.
package struct ButtonPlace: Codable, Equatable, Sendable {
    /// The kinds of element around it, its parent first, up to the page:
    /// e.g. "AXGroup", "AXToolbar", "AXGroup:AXLandmarkComplementary". Never
    /// their names, which are in the site's language and can change.
    package let path: [String]
    /// Points from its middle to the bottom of its window: players keep
    /// their controls at the bottom.
    package let distanceFromBottom: Double

    package init(path: [String], distanceFromBottom: Double) {
        self.path = path
        self.distanceFromBottom = distanceFromBottom
    }
}

/// A web app's pages, read and pressed through Accessibility. Calls block:
/// `SafariWebAppPlayer` makes them on a queue of its own. A protocol, so
/// tests can stand in for it.
package protocol WebPage: Sendable {
    /// Whether AutoHush may use Accessibility; `prompt` shows macOS's request.
    func isTrusted(prompt: Bool) -> Bool
    /// The buttons on the pages in the app's windows, on any Space; `nil`
    /// while it has no window.
    func buttons(pid: pid_t) -> [PageButton]?
    /// Whether the app has a window, on any Space (minimized ones too).
    func hasWindow(pid: pid_t) -> Bool
    /// The button as it is now; `nil` once it's gone (the page reloaded) or
    /// doesn't answer.
    func button(_ handle: ButtonHandle) -> PageButton?
    /// Where the button is; `nil` once it's gone.
    func place(of handle: ButtonHandle) -> ButtonPlace?
    /// Whether it's in sight and among a player's controls, for learning;
    /// `nil` once it's gone.
    func standing(of handle: ButtonHandle) -> ButtonStanding?
    /// Presses it; `false` when that wasn't possible.
    func press(_ handle: ButtonHandle) -> Bool
    /// Whether the app's sound is on: a process it's responsible for (its
    /// WebKit process) has output running.
    func isPlayingSound(pid: pid_t) -> Bool
    /// Whether its page's words are current now: a WebKit page's always; a
    /// Chromium or Flutter page's only while one of its windows can be seen.
    func wordsAreCurrent(pid: pid_t) -> Bool
    /// Turns back off the switch it turned on to show the app's page, now
    /// that the app is no longer the player.
    func release()
    /// The page's word was current and said whether it plays: a Chromium web
    /// app's page counts its browser's other playing pages then, to tell its
    /// own sound from theirs while its word isn't current.
    func noteState(playing: Bool, pid: pid_t)
}

extension WebPage {
    package func wordsAreCurrent(pid: pid_t) -> Bool { true }
    package func noteState(playing: Bool, pid: pid_t) {}
}

/// The real pages, through the Accessibility API, which WebKit offers for
/// every page without any setting. Another app's page (`PageAccess`: an
/// Electron, CEF or Flutter app's, a Chromium browser's web app's) shows once
/// its switch for assistive tools is on: it's turned on before the first
/// look, on the process that serves the page, and kept on until the last
/// page using it in AutoHush is released (`SharedSwitches`).
///
/// Windows on another Space are reached through `AccessibilityWindows`, a
/// private function; the public list has only the current Space's.
package struct AccessibilityWebPage: WebPage {
    /// How long to wait for the app to answer each read (its windows, and
    /// each element a walk reads), so a stuck page can't hold AutoHush up.
    package static let timeout: Float = 0.5
    /// The page is this deep in a window at most (measured: 3 to 5), and
    /// found among this many of the window's elements, read breadth first,
    /// not walking into lists: a native app's window isn't read whole.
    private static let webAreaDepth = 16
    private static let webAreaReadLimit = 2000
    /// A Flutter window's pressable items are this deep at most, among this
    /// many of its elements.
    private static let itemDepth = 40
    private static let itemReadLimit = 3000
    /// Roles never walked into looking for a page: a native app's long lists
    /// (Music's songs) hold none.
    private static let listRoles: Set<String> = [kAXTableRole, kAXOutlineRole, kAXBrowserRole, kAXListRole, "AXGrid", kAXTextAreaRole]
    /// A button is this deep in its page at most.
    private static let pathDepth = 60
    /// A player's controls are looked for in this many elements around a
    /// button (its parent first), each this deep, with at most this many
    /// elements read in all: a player bar's slider is in its button's
    /// parent on SoundCloud and YouTube Music (`playerBar(around:)`).
    private static let controlsLevels = 3
    private static let controlsDepth = 6
    private static let controlsReadLimit = 500
    /// The web app's own audio processes, kept between checks of its sound.
    private let audioProcesses = OwnedAudioProcesses()
    /// How the app shows its page.
    let access: PageAccess
    /// This page, among the users of a switch (its copies are the same page).
    private let id = UUID()
    /// Every page's switches, shared.
    private static let switches = SharedSwitches()
    /// A Chromium web app's browser's other playing pages, counted when the
    /// web app's state was last known; `nil` until then, and once they changed.
    private let otherPages = OSAllocatedUnfairLock<Int?>(initialState: nil)

    package init(access: PageAccess = .webKit) {
        self.access = access
    }

    package func isTrusted(prompt: Bool) -> Bool {
        AccessibilityPermission.isTrusted(prompt: prompt)
    }

    package func hasWindow(pid: pid_t) -> Bool {
        !windows(of: pid).isEmpty
    }

    package func buttons(pid: pid_t) -> [PageButton]? {
        showPage(pid: pid)
        let windows = windows(of: pid)
        guard !windows.isEmpty else { return nil }
        return windows.flatMap { Self.pageElements(in: $0, access: access) }.compactMap { button(ButtonHandle($0)) }
    }

    /// The buttons of the pages in `window` (each web area's, by
    /// Accessibility's search for buttons), or a Flutter window's items that
    /// can be pressed, each read waiting `timeout`. Player Check finds a
    /// page's buttons with this, so a check keeps only a page way AutoHush
    /// can press.
    package static func pageElements(in window: AXUIElement, access: PageAccess) -> [AXUIElement] {
        if access.pageIsWindow { return pressableItems(in: window) }
        let search: [String: Any] = [
            "AXSearchKey": "AXButtonSearchKey", "AXResultsLimit": 2000, "AXDirection": "AXDirectionNext",
            "AXVisibleOnly": false, "AXImmediateDescendantsOnly": false,
        ]
        return webAreas(in: window).flatMap { area -> [AXUIElement] in
            var result: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                area, "AXUIElementsForSearchPredicate" as CFString, search as CFDictionary, &result
            ) == .success else { return [] }
            return AXUIElement.elements(in: result).map { $0.waiting(timeout) }
        }
    }

    /// What a page's button is called: what it says to VoiceOver (its
    /// description), else its title; a Flutter app's item, else its value
    /// (a pressable text keeps its words there).
    package static func label(of element: AXUIElement, access: PageAccess) -> String {
        label(of: element, access: access, description: element.string(kAXDescriptionAttribute))
    }

    /// `label(of:access:)`, its description read already; the others are
    /// read only while it says nothing.
    private static func label(of element: AXUIElement, access: PageAccess, description: String?) -> String {
        func said(_ text: String?) -> String? { text.flatMap { $0.isEmpty ? nil : $0 } }
        return said(description) ?? said(element.string(kAXTitleAttribute))
            ?? (access.pageIsWindow ? said(element.string(kAXValueAttribute)) : nil) ?? ""
    }

    package func button(_ handle: ButtonHandle) -> PageButton? {
        guard let element = Self.element(of: handle) else { return nil }
        var description: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description) {
        case .invalidUIElement, .cannotComplete: return nil // gone, or not answering
        default: break
        }
        let label = Self.label(of: element, access: access, description: description as? String)
        // Only one that says so is disabled: a Flutter item may not say.
        let enabled = element.value(kAXEnabledAttribute) as? Bool ?? true
        return PageButton(handle: handle, label: label, isEnabled: enabled)
    }

    package func place(of handle: ButtonHandle) -> ButtonPlace? {
        guard let element = Self.element(of: handle), let frame = element.frame else { return nil }
        let (around, window) = Self.surroundings(of: element)
        guard let window, let windowFrame = window.frame else { return nil }
        let path = around.map { node, role in node.string(kAXSubroleAttribute).map { "\(role):\($0)" } ?? role }
        return ButtonPlace(path: path, distanceFromBottom: windowFrame.maxY - frame.midY)
    }

    package func standing(of handle: ButtonHandle) -> ButtonStanding? {
        guard let element = Self.element(of: handle), let frame = element.frame else { return nil }
        let (around, window) = Self.surroundings(of: element)
        guard let window, let windowFrame = window.frame else { return nil }
        return ButtonStanding(isInWindow: (windowFrame.minY...windowFrame.maxY).contains(frame.midY),
                              isWithPlayerControls: Self.playerBar(among: around.map(\.element)) != nil)
    }

    /// The player's bar around a page's button: the nearest of the
    /// `controlsLevels` elements around it in its page (its parent first)
    /// that holds a slider or a progress bar, as a player's bar does; `nil`
    /// without one. What learning weighs (`ButtonStanding.isWithPlayerControls`);
    /// Player Check ranks a page's buttons by it.
    package static func playerBar(around element: AXUIElement) -> AXUIElement? {
        var around: [AXUIElement] = []
        var node = element
        while around.count < controlsLevels, let parent = node.element(kAXParentAttribute, timeout: timeout) {
            node = parent
            let role = node.string(kAXRoleAttribute)
            if role == "AXWebArea" || role == kAXWindowRole { break }
            around.append(node)
        }
        return playerBar(among: around)
    }

    /// The first of `around`'s `controlsLevels` elements holding a slider or
    /// a progress bar, each read `controlsDepth` deep, `controlsReadLimit`
    /// elements in all.
    private static func playerBar(among around: [AXUIElement]) -> AXUIElement? {
        var reads = controlsReadLimit
        return around.prefix(controlsLevels).first { holdsSlider($0, depth: 0, reads: &reads) }
    }

    /// The texts of the player's bar around the page's button saying one of
    /// `labels` (its Play/Pause's words): the song and the artist, where the
    /// window's title may not name them. The bar is the nearest element
    /// around the button holding a slider or a progress bar
    /// (`playerBar(around:)`, as `standing` looks for one); its texts are read at most `barTextDepth` deep. None
    /// without such a button or bar. `PanelWay` tells the app's row in the
    /// Now Playing panel by them, as its check did (2026-10-19).
    package func playerBarTexts(pid: pid_t, labels: Set<String>) -> [String] {
        for button in buttons(pid: pid) ?? [] where labels.contains(button.label) {
            guard let element = Self.element(of: button.handle), let bar = Self.playerBar(around: element) else { continue }
            var texts: [String] = []
            Self.walk(from: bar, limit: Self.controlsReadLimit, maxDepth: Self.barTextDepth) { element, _ in
                texts += [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].compactMap { element.string($0) }.filter { !$0.isEmpty }
                return true
            }
            return texts
        }
        return []
    }

    /// A player bar's texts are this deep in it at most.
    private static let barTextDepth = 8

    /// The elements around `element` in its page, its parent first, with
    /// their roles (the page itself, and what holds it, aren't among them),
    /// and the window it's in; `nil` for a window not found within
    /// `pathDepth` parents.
    private static func surroundings(of element: AXUIElement)
        -> (inPage: [(element: AXUIElement, role: String)], window: AXUIElement?) {
        var inPage: [(element: AXUIElement, role: String)] = []
        var node = element
        var pastPage = false
        for _ in 0..<pathDepth {
            guard let parent = node.element(kAXParentAttribute, timeout: timeout) else { break }
            node = parent
            let role = node.string(kAXRoleAttribute) ?? ""
            if role == kAXWindowRole { return (inPage, node) }
            if role == "AXWebArea" { pastPage = true }
            if !pastPage { inPage.append((node, role)) } // else on to its window
        }
        return (inPage, nil)
    }

    /// Whether a slider or a progress bar is in `element`, as a player's
    /// controls have; `reads` counts the elements it may still read.
    private static func holdsSlider(_ element: AXUIElement, depth: Int, reads: inout Int) -> Bool {
        guard reads > 0 else { return false }
        reads -= 1
        let role = element.string(kAXRoleAttribute)
        if role == kAXSliderRole || role == kAXProgressIndicatorRole { return true }
        guard depth < controlsDepth else { return false }
        for child in element.children(timeout: timeout) where holdsSlider(child, depth: depth + 1, reads: &reads) { return true }
        return false
    }

    package func press(_ handle: ButtonHandle) -> Bool {
        guard let element = Self.element(of: handle) else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    package func isPlayingSound(pid: pid_t) -> Bool {
        guard access.browserID != nil else { return audioProcesses.isPlayingSound(appPID: pid) }
        // A Chromium web app's sound is its browser's, shared with its tabs:
        // its own is one "Playing audio" assertion more than its other pages'.
        let browser = switchTarget(pid)
        let total = PlayingPages.count(ofBrowser: browser)
        if let others = otherPages.withLock({ $0 }) {
            if let plays = PlayingPages.webAppPlays(total: total, others: others) { return plays }
            otherPages.withLock { $0 = nil } // another page started or stopped
        }
        return audioProcesses.isPlayingSound(appPID: browser)
    }

    package func noteState(playing: Bool, pid: pid_t) {
        guard access.browserID != nil else { return }
        let total = PlayingPages.count(ofBrowser: switchTarget(pid))
        otherPages.withLock { $0 = playing ? max(total - 1, 0) : total }
    }

    package func wordsAreCurrent(pid: pid_t) -> Bool {
        guard !access.wordsCurrentOutOfSight else { return true }
        // Seen: the app isn't hidden, and a window of it on this desktop isn't minimized.
        guard NSRunningApplication(processIdentifier: pid)?.isHidden == false else { return false }
        return AXUIElement.application(pid, timeout: Self.timeout).elements(kAXWindowsAttribute, timeout: Self.timeout)
            .contains { $0.value(kAXMinimizedAttribute) as? Bool != true }
    }

    /// Its switches go back off, those AutoHush turned on that no other page
    /// of AutoHush uses still.
    package func release() {
        Self.switches.release(id) { key in
            AXUIElementSetAttributeValue(AXUIElement.application(key.process, timeout: Self.timeout), key.attribute as CFString, kCFBooleanFalse)
        }
    }

    // MARK: - The switch

    /// Turns its switch on, on the process that serves its page, at its
    /// first look on that process (the app opened again is a new one):
    /// Chromium builds the page for assistive tools from then on, and
    /// Electron takes presses about 2 s later. Kept on: a press that turned
    /// it on and off again would lose the page out of sight (Player Check,
    /// 2026-10-12). VoiceOver's, which reads back as it is, is read at each
    /// look, and turned on again when another tool turned it off (a check of
    /// another web app of the same browser, at its end).
    private func showPage(pid: pid_t) {
        guard let attribute = access.switchAttribute else { return }
        let process = switchTarget(pid)
        let app = AXUIElement.application(process, timeout: Self.timeout)
        Self.switches.use(attribute, on: process, by: id, readsBack: attribute == PageAccess.voiceOverSwitch, isOn: {
            // Electron's reads back off even while it's on (Deezer): its page
            // showing tells it's on.
            app.value(attribute) as? Bool == true
                || (attribute == PageAccess.electronSwitch && windows(of: pid).contains { !Self.webAreas(in: $0).isEmpty })
        }, turnOn: {
            AXUIElementSetAttributeValue(app, attribute as CFString, kCFBooleanTrue)
        })
    }

    /// The process its switch is set on: a Chromium web app's browser (its
    /// own process serves the page), else the app.
    private func switchTarget(_ pid: pid_t) -> pid_t { Self.switchTarget(pid, access: access) }

    /// The process the switch of a page shown as `access` says is set on, for
    /// the app running as `pid`: a Chromium web app's browser (its own
    /// process serves the page; set on the web app, nothing shows), else the
    /// app. Player Check sets its switches there too.
    package static func switchTarget(_ pid: pid_t, access: PageAccess) -> pid_t {
        guard let browserID = access.browserID, let browser = NSRunningApplication.running(browserID) else { return pid }
        return browser.processIdentifier
    }

    // MARK: - Windows and pages

    /// The app's windows on the current Space (minimized ones too), else on
    /// any Space.
    private func windows(of pid: pid_t) -> [AXUIElement] { Self.windows(of: pid).windows }

    /// The windows of the app running as `pid` on the current Space
    /// (minimized ones too), else on any other (`elsewhere`: through
    /// `AccessibilityWindows`, about 70 ms), each read waiting `timeout`;
    /// `onThisDesktop` false for those. Player Check finds an app's windows
    /// with this (keeping those found elsewhere a while, and waiting longer).
    package static func windows(of pid: pid_t, timeout: Float = AccessibilityWebPage.timeout,
                                elsewhere: (pid_t) -> [AXUIElement]? = AccessibilityWindows.windows(ofProcess:))
        -> (windows: [AXUIElement], onThisDesktop: Bool) {
        let shown = AXUIElement.application(pid, timeout: timeout).elements(kAXWindowsAttribute, timeout: timeout)
        guard shown.isEmpty else { return (shown, true) }
        return ((elsewhere(pid) ?? []).map { $0.waiting(timeout) }, false)
    }

    /// The web pages (AXWebArea) in a window, nearest first, reading at most
    /// `webAreaReadLimit` of its elements and none inside a list.
    package static func webAreas(in window: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        walk(from: window, limit: webAreaReadLimit, maxDepth: webAreaDepth) { element, _ in
            let role = element.string(kAXRoleAttribute) ?? ""
            if role == "AXWebArea" {
                found.append(element)
                return false
            }
            return !listRoles.contains(role)
        }
        return found
    }

    /// A Flutter window's items that can be pressed (its buttons, and the
    /// texts and images it marks pressable); not the window's own close,
    /// minimize and full-screen buttons.
    static func pressableItems(in window: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        walk(from: window, limit: itemReadLimit, maxDepth: itemDepth) { element, depth in
            if depth == 1, element.string(kAXRoleAttribute) == kAXButtonRole { return false }
            if depth > 0, element.actionNames.contains(kAXPressAction) { found.append(element) }
            return true
        }
        return found
    }

    /// Walks an element's tree breadth first, reading at most `limit`
    /// elements and going at most `maxDepth` levels down, each read waiting
    /// `timeout`; `visit` says whether to go into each one's children.
    static func walk(from root: AXUIElement, limit: Int, maxDepth: Int, _ visit: (AXUIElement, Int) -> Bool) {
        var queue: [(AXUIElement, Int)] = [(root, 0)], next = 0
        while next < queue.count, next < limit {
            let (element, depth) = queue[next]
            next += 1
            if visit(element, depth), depth < maxDepth { queue += element.children(timeout: timeout).map { ($0, depth + 1) } }
        }
    }

    // MARK: - Accessibility values

    private static func element(of handle: ButtonHandle) -> AXUIElement? {
        guard let element = handle.element.base as AnyObject?, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        return (element as! AXUIElement)
    }

}
