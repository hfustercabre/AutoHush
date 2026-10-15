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
    package let isEnabled: Bool

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
    package let isInWindow: Bool
    /// Something just around it holds a slider or a progress bar, as a
    /// player's bar does (its progress, its volume).
    package let isWithPlayerControls: Bool

    package init(isInWindow: Bool = true, isWithPlayerControls: Bool = false) {
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
    package func release() {}
    package func noteState(playing: Bool, pid: pid_t) {}
}

/// The real pages, through the Accessibility API, which WebKit offers for
/// every page without any setting. Another app's page (`PageAccess`: an
/// Electron, CEF or Flutter app's, a Chromium browser's web app's) shows once
/// its switch for assistive tools is on: it's turned on before the first
/// look, on the process that serves the page, and kept on until `release`.
///
/// Windows on another Space are reached through `AccessibilityWindows`, a
/// private function; the public list has only the current Space's.
package struct AccessibilityWebPage: WebPage {
    /// How long to wait for the app to answer, so a stuck page can't hold
    /// AutoHush up.
    package static let timeout: Float = 0.5
    /// The page is this deep in a window at most (measured: 3 to 5).
    private static let webAreaDepth = 16
    /// A button is this deep in its page at most.
    private static let pathDepth = 60
    /// A player's controls are looked for in this many elements around a
    /// button (its parent first), each this deep, with at most this many
    /// elements read in all: a player bar's slider is in its button's
    /// parent on SoundCloud and YouTube Music.
    private static let controlsLevels = 3
    private static let controlsDepth = 6
    private static let controlsReadLimit = 500
    /// The web app's own audio processes, kept between checks of its sound.
    private let audioProcesses = OwnedAudioProcesses()
    /// How the app shows its page.
    package let access: PageAccess
    /// The processes whose switch this page turned on, and whether each was
    /// on before.
    private let switched = OSAllocatedUnfairLock<[pid_t: Bool]>(initialState: [:])
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
        let search: [String: Any] = [
            "AXSearchKey": "AXButtonSearchKey", "AXResultsLimit": 2000, "AXDirection": "AXDirectionNext",
            "AXVisibleOnly": false, "AXImmediateDescendantsOnly": false,
        ]
        return windows.flatMap { access.pageIsWindow ? [$0] : Self.webAreas(in: $0) }.flatMap { area -> [PageButton] in
            var result: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                area, "AXUIElementsForSearchPredicate" as CFString, search as CFDictionary, &result
            ) == .success else { return [] }
            return AXUIElement.elements(in: result).compactMap { element in
                // Each element waits macOS's default 6 s otherwise.
                AXUIElementSetMessagingTimeout(element, Self.timeout)
                return button(ButtonHandle(element))
            }
        }
    }

    package func button(_ handle: ButtonHandle) -> PageButton? {
        guard let element = Self.element(of: handle) else { return nil }
        var description: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description) {
        case .invalidUIElement, .cannotComplete: return nil // gone, or not answering
        default: break
        }
        let label = [description as? String, element.string(kAXTitleAttribute)]
            .compactMap { $0 }.first { !$0.isEmpty } ?? ""
        let enabled = element.value(kAXEnabledAttribute) as? Bool ?? false
        return PageButton(handle: handle, label: label, isEnabled: enabled)
    }

    package func place(of handle: ButtonHandle) -> ButtonPlace? {
        guard let element = Self.element(of: handle), let frame = Self.frame(of: element) else { return nil }
        let (around, window) = Self.surroundings(of: element)
        guard let window, let windowFrame = Self.frame(of: window) else { return nil }
        let path = around.map { node, role in node.string(kAXSubroleAttribute).map { "\(role):\($0)" } ?? role }
        return ButtonPlace(path: path, distanceFromBottom: windowFrame.maxY - frame.midY)
    }

    package func standing(of handle: ButtonHandle) -> ButtonStanding? {
        guard let element = Self.element(of: handle), let frame = Self.frame(of: element) else { return nil }
        let (around, window) = Self.surroundings(of: element)
        guard let window, let windowFrame = Self.frame(of: window) else { return nil }
        var reads = Self.controlsReadLimit
        let withControls = around.prefix(Self.controlsLevels).contains { Self.holdsSlider($0.element, depth: 0, reads: &reads) }
        return ButtonStanding(isInWindow: (windowFrame.minY...windowFrame.maxY).contains(frame.midY),
                              isWithPlayerControls: withControls)
    }

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
            guard let parent = node.element(kAXParentAttribute) else { break }
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
        for child in element.children where holdsSlider(child, depth: depth + 1, reads: &reads) { return true }
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
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        return app.elements(kAXWindowsAttribute).contains { $0.value(kAXMinimizedAttribute) as? Bool != true }
    }

    package func release() {
        guard let attribute = access.switchAttribute else { return }
        let turnedOn = switched.withLock { switched in
            defer { switched = [:] }
            return switched.filter { !$0.value }.map(\.key)
        }
        for pid in turnedOn {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, Self.timeout)
            AXUIElementSetAttributeValue(app, attribute as CFString, kCFBooleanFalse)
        }
    }

    // MARK: - The switch

    /// Turns its switch on, on the process that serves its page, once per
    /// process (the app opened again is a new one): Chromium builds the page
    /// for assistive tools from then on, and Electron takes presses about 2 s
    /// later. Kept on: a press that turned it on and off again would lose
    /// the page out of sight (Player Check, 2026-10-12).
    private func showPage(pid: pid_t) {
        guard let attribute = access.switchAttribute else { return }
        let target = switchTarget(pid)
        guard switched.withLock({ $0[target] == nil }) else { return }
        let app = AXUIElementCreateApplication(target)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        let wasOn = app.value(attribute) as? Bool ?? false
        if !wasOn { AXUIElementSetAttributeValue(app, attribute as CFString, kCFBooleanTrue) }
        switched.withLock { $0[target] = wasOn }
    }

    /// The process its switch is set on: a Chromium web app's browser (its
    /// own process serves the page), else the app.
    private func switchTarget(_ pid: pid_t) -> pid_t {
        guard let browserID = access.browserID, let browser = NSRunningApplication.running(browserID) else { return pid }
        return browser.processIdentifier
    }

    // MARK: - Windows and pages

    /// The app's windows on the current Space (minimized ones too), else on
    /// any Space.
    private func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        let shown = app.elements(kAXWindowsAttribute)
        let windows = shown.isEmpty ? (AccessibilityWindows.windows(ofProcess: pid) ?? []) : shown
        windows.forEach { AXUIElementSetMessagingTimeout($0, Self.timeout) }
        return windows
    }

    private static func webAreas(in element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        if element.string(kAXRoleAttribute) == "AXWebArea" { return [element] }
        guard depth < webAreaDepth else { return [] }
        return element.children.flatMap { webAreas(in: $0, depth: depth + 1) }
    }

    // MARK: - Accessibility values

    private static func element(of handle: ButtonHandle) -> AXUIElement? {
        guard let element = handle.element.base as AnyObject?, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        return (element as! AXUIElement)
    }

    /// Its frame on screen, from the top left corner.
    private static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = element.value(kAXPositionAttribute), let extent = element.value(kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(extent) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(extent as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
