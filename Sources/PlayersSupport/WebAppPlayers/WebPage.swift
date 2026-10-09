import ApplicationServices
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
package struct ButtonPlace: Equatable, Sendable {
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
}

/// The real pages, through the Accessibility API, which WebKit offers for
/// every page without any setting.
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

    package init() {}

    package func isTrusted(prompt: Bool) -> Bool {
        AccessibilityPermission.isTrusted(prompt: prompt)
    }

    package func hasWindow(pid: pid_t) -> Bool {
        !windows(of: pid).isEmpty
    }

    package func buttons(pid: pid_t) -> [PageButton]? {
        let windows = windows(of: pid)
        guard !windows.isEmpty else { return nil }
        let search: [String: Any] = [
            "AXSearchKey": "AXButtonSearchKey", "AXResultsLimit": 2000, "AXDirection": "AXDirectionNext",
            "AXVisibleOnly": false, "AXImmediateDescendantsOnly": false,
        ]
        return windows.flatMap { Self.webAreas(in: $0) }.flatMap { area -> [PageButton] in
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
        var path: [String] = []
        var node = element
        var window: AXUIElement?
        var inPage = true
        for _ in 0..<Self.pathDepth {
            guard let parent = node.element(kAXParentAttribute) else { break }
            node = parent
            let role = node.string(kAXRoleAttribute) ?? ""
            if role == kAXWindowRole {
                window = node
                break
            }
            if role == "AXWebArea" { inPage = false }
            guard inPage else { continue } // on to its window
            let subrole = node.string(kAXSubroleAttribute)
            path.append(subrole.map { "\(role):\($0)" } ?? role)
        }
        guard let window, let windowFrame = Self.frame(of: window) else { return nil }
        return ButtonPlace(path: path, distanceFromBottom: windowFrame.maxY - frame.midY)
    }

    package func standing(of handle: ButtonHandle) -> ButtonStanding? {
        guard let element = Self.element(of: handle), let frame = Self.frame(of: element) else { return nil }
        var around: [AXUIElement] = []
        var node = element
        var window: AXUIElement?
        var inPage = true
        for _ in 0..<Self.pathDepth {
            guard let parent = node.element(kAXParentAttribute) else { break }
            node = parent
            let role = node.string(kAXRoleAttribute) ?? ""
            if role == kAXWindowRole {
                window = node
                break
            }
            if role == "AXWebArea" { inPage = false }
            if inPage, around.count < Self.controlsLevels { around.append(node) }
        }
        guard let window, let windowFrame = Self.frame(of: window) else { return nil }
        var reads = Self.controlsReadLimit
        let withControls = around.contains { Self.holdsSlider($0, depth: 0, reads: &reads) }
        return ButtonStanding(isInWindow: (windowFrame.minY...windowFrame.maxY).contains(frame.midY),
                              isWithPlayerControls: withControls)
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
        audioProcesses.isPlayingSound(appPID: pid)
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
