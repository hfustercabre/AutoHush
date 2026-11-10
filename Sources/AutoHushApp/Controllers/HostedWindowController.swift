import AppKit
import Observation
import SwiftUI

/// A window around SwiftUI content, sized to it: closable, minimizable (⌘M),
/// never full screen, and kept when closed, so it shows again at once. Its title bar is part of it, as in
/// Settings (no band, no line), with the title in bold as a Settings page's
/// name. It's shown in front, and centered when it comes on screen, or,
/// floating above other apps, in the top-right corner (`floatsInCorner`).
/// Given `keys`, the arrow keys and the pointer move a highlight through its
/// controls, as in Settings (`WindowKeys`).
/// The welcome, learning, "Add a Web App", "Add an App", "Choose an App"
/// and check warning windows are these; the learning and "Add a Web App"
/// windows float. The logs window, which the user resizes, has its own
/// (`LogsWindowController`).
@MainActor
class HostedWindowController: NSWindowController {
    /// The content's side and bottom margins (`windowMargins`).
    static let margin: CGFloat = 20

    /// `floatsInCorner`: whether it floats in the top-right corner, above
    /// other apps' windows. `keys`: its keys (`WindowKeys`), given to
    /// `content`'s view too (`windowKeys(_:)`).
    init(content: NSViewController, title: String, floatsInCorner: Bool = false, keys: WindowKeys? = nil) {
        let window = NSWindow(contentViewController: content)
        window.title = title
        Self.styleTitleBar(of: window)
        if floatsInCorner {
            window.level = .floating
            // Over another app's full-screen window too (Safari, the web
            // app); an auxiliary window doesn't go full screen itself.
            window.collectionBehavior.insert(.fullScreenAuxiliary)
        } else {
            // No AutoHush window goes full screen: the green button, ⌃⌘F and the
            // Window menu leave it as it is.
            window.collectionBehavior.insert(.fullScreenNone)
        }
        window.isReleasedWhenClosed = false
        self.floatsInCorner = floatsInCorner
        self.keys = keys
        super.init(window: window)
        if let keys { connect(keys) }
    }

    /// Settings' title bar, with an empty toolbar. The content
    /// starts below it, not under it: with it under the title bar, SwiftUI
    /// follows the title bar's inset, and on macOS 14 and 15 each resize to
    /// the content changed that inset and asked for layout again, until
    /// AppKit threw (Add an App's window as its check started, 2026-10-20).
    private static func styleTitleBar(of window: NSWindow) {
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.useAutoHushTitleBar(NSToolbar(identifier: "AutoHushWindow"))
    }

    /// How much of the window's height the title bar takes (its toolbar's
    /// room included): the content gets the rest.
    static let titleBarHeight: CGFloat = {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: true)
        styleTitleBar(of: window)
        return window.frame.height - window.contentLayoutRect.height
    }()

    /// Keeps the window's title as `title` says while what it reads changes
    /// (the page shown, the player's name).
    func followTitle(_ title: @escaping @MainActor @Sendable () -> String) {
        window?.title = title()
        withObservationTracking { _ = title() } onChange: { [weak self] in
            Task { @MainActor in self?.followTitle(title) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Above every app's windows, in the top-right corner of the screen: for
    /// a window that guides the user through other apps (Safari, a web app),
    /// which come in front and would hide it while the user works there. The
    /// corner keeps it off Safari's dialog and a web app's player bar. It
    /// keeps its top edge as its steps come and go.
    let floatsInCorner: Bool

    /// The top edge kept while it floats; the user moving it moves it.
    private var pinnedTop: CGFloat?
    /// What keeps the top edge, from when it floats on screen until it
    /// closes (`watchTopEdge`).
    private(set) var edgeObservers: [any NSObjectProtocol] = []
    static let cornerMargin: CGFloat = 16
    /// The screen it floats on: the one the user is on, with the pointer
    /// (tests pick one).
    var cornerScreen: @MainActor () -> NSScreen? = {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    /// A hosting controller for `view` that sizes the window to it.
    static func sizedToFit<Content: View>(_ view: Content) -> NSHostingController<Content> {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        return hosting
    }

    /// Shown and not closed since: on screen, minimized, or hidden with AutoHush (⌘H).
    var isOpen: Bool { window?.isOpen == true }

    func show() {
        guard let window else { return }
        let opening = !window.isOpen
        if opening {
            // Sized to its content first: centered at its first, empty size,
            // it would grow from the middle of the screen, partly off it.
            if let fitting = window.contentView?.fittingSize, fitting.width > 0, fitting.height > 0 {
                window.setContentSize(fitting)
            }
            if floatsInCorner {
                if let area = cornerScreen()?.visibleFrame {
                    window.setFrameTopLeftPoint(NSPoint(x: area.maxX - window.frame.width - Self.cornerMargin,
                                                        y: area.maxY - Self.cornerMargin))
                }
                pinnedTop = window.frame.maxY
                watchTopEdge()
            } else {
                window.center()
            }
        }
        if opening { keys?.highlight.clear() } // nothing lit as it opens
        watchKeys()
        window.showInFront()
        // With keys, nothing focused as it opens, but a field typed into,
        // as Settings and the menu open: the first ↓ shows where the keys
        // are (N6, 2026-11-06: with keyboard navigation on, the check
        // warning opened with Cancel focused, and → did nothing on it).
        if opening, keys != nil, !(window.firstResponder is NSText) { window.makeFirstResponder(nil) }
    }

    /// While it floats, a change of size keeps its top edge where it was, so
    /// it never grows off the top of the screen; a move by the user is kept.
    /// Until it closes: each Learn Again makes a new window, and the closed
    /// one's watch would stay behind.
    private func watchTopEdge() {
        stopWatchingTopEdge()
        guard let window else { return }
        let center = NotificationCenter.default
        edgeObservers = [
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window, let top = self.pinnedTop, window.frame.maxY != top else { return }
                    window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
                }
            },
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window, window.isVisible else { return }
                    self.pinnedTop = window.frame.maxY
                }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopWatchingTopEdge() }
            },
        ]
    }

    private func stopWatchingTopEdge() {
        edgeObservers.forEach(NotificationCenter.default.removeObserver)
        edgeObservers = []
    }

    // MARK: - Off another app's dialog

    /// Where it was before `moveAside(of:)` moved it, and where it put it
    /// (top left corners).
    private var aside: (from: NSPoint, to: NSPoint)?

    /// Moved beside `obstacle` (another app's dialog, from the main
    /// screen's top left corner, as Accessibility gives it) when it covers
    /// part of it: to its left, else its right, its top edge kept, else
    /// below it, on its screen (the 1.3.0 live round, 2026-11-05: Add a
    /// Web App covered Safari's Add button; the user, 2026-11-06: "Okay,
    /// move it"). Left where it is when it covers none of it, or nowhere
    /// fits; `returnFromAside()` puts it back.
    func moveAside(of obstacle: CGRect) {
        guard aside == nil, let window, window.isVisible, let main = NSScreen.screens.first else { return }
        let dialog = NSRect(x: obstacle.minX, y: main.frame.maxY - obstacle.maxY, width: obstacle.width, height: obstacle.height)
        let frame = window.frame
        guard frame.intersects(dialog), let area = (window.screen ?? cornerScreen())?.visibleFrame else { return }
        let gap = Self.cornerMargin
        let places = [
            NSPoint(x: dialog.minX - gap - frame.width, y: frame.maxY),
            NSPoint(x: dialog.maxX + gap, y: frame.maxY),
            NSPoint(x: frame.minX, y: dialog.minY - gap),
        ]
        guard let place = places.first(where: { topLeft in
            let moved = NSRect(x: topLeft.x, y: topLeft.y - frame.height, width: frame.width, height: frame.height)
            return area.contains(moved) && !moved.intersects(dialog)
        }) else { return }
        aside = (from: NSPoint(x: frame.minX, y: frame.maxY), to: place)
        window.setFrameTopLeftPoint(place)
    }

    /// Back where it was before `moveAside(of:)`, unless the user moved it
    /// since.
    func returnFromAside() {
        guard let aside, let window else { return }
        self.aside = nil
        guard abs(window.frame.minX - aside.to.x) < 1, abs(window.frame.maxY - aside.to.y) < 1 else { return }
        window.setFrameTopLeftPoint(aside.from)
    }

    // MARK: - The keys

    /// The highlight the arrow keys and the pointer move (`WindowKeys`), if
    /// the window has one.
    let keys: WindowKeys?
    /// macOS's keyboard navigation setting, read at each key (tests set it).
    var fullKeyboardAccess: @MainActor () -> Bool = { NSApp.isFullKeyboardAccessEnabled }
    /// The keys' monitor, from when it shows until it closes: each Learn
    /// Again and each check makes a new window.
    private var keyMonitor: Any?
    private var keyCloseObserver: (any NSObjectProtocol)?

    /// What the keys do to the window: the focus let go, Zoom told where
    /// the highlight is (A3).
    private func connect(_ keys: WindowKeys) {
        keys.dropFocus = { [weak self] in _ = self?.window?.makeFirstResponder(nil) }
        keys.highlight.place { [weak self] in self?.window?.contentView }
    }

    /// Before the focused control, as Settings' keys are, until it closes.
    private func watchKeys() {
        guard keys != nil, keyMonitor == nil, let window else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode, flags = event.modifierFlags, characters = event.characters
            let windowNumber = event.windowNumber
            let handled = MainActor.assumeIsolated {
                self?.handleKey(keyCode, flags: flags, characters: characters, windowNumber: windowNumber) == true
            }
            return handled ? nil : event
        }
        keyCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopWatchingKeys() }
        }
    }

    private func stopWatchingKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let keyCloseObserver { NotificationCenter.default.removeObserver(keyCloseObserver) }
        keyCloseObserver = nil
    }

    /// The window's keys, as `WindowKeys` takes them (`HighlightKey`, the
    /// menu's and Settings' mapping, and letters typed), not in a sheet nor
    /// while an input method composes, as in Settings and the menu
    /// (`WindowKeyPress`). `false` leaves the key to the window.
    func handleKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?, windowNumber: Int) -> Bool {
        guard let keys, let window, let press = WindowKeyPress(keyCode, flags: flags, windowNumber: windowNumber, in: window,
                                                               fullKeyboardAccess: fullKeyboardAccess) else { return false }
        if let key = press.key { return keys.handle(key, focus: press.focus) }
        if WindowKeys.isTyped(characters, modifiers: flags) { keys.typed(focus: press.focus) }
        return false
    }

    /// The window's search takes the keyboard, the caret after its text, for
    /// what's typed (`WindowKeys.focusSearch`); `false` when none shows.
    func focusSearch() -> Bool {
        guard let window, let field = window.contentView?.firstEditableTextField, window.makeFirstResponder(field) else { return false }
        field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        return true
    }

    /// Brings it in front of other apps' windows, on the desktop the user is
    /// on, without making it key: for while AutoHush's menu opens.
    func bringForward() {
        guard window?.isVisible == true else { return }
        window?.bringForward()
    }
}
