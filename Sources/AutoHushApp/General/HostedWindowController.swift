import AppKit
import Observation
import SwiftUI

/// A window around SwiftUI content, sized to it: closable, and kept when
/// closed, so it shows again at once. Its title bar is part of it, as in
/// Settings (no band, no line), with the title in bold as a Settings page's
/// name. It's shown in front, and centered when it comes on screen, or,
/// floating above other apps, in the top-right corner (`floatsInCorner`).
/// The welcome, learning and "Add a Web App" windows are these; the last
/// two float.
@MainActor
class HostedWindowController: NSWindowController {
    /// The content's side and bottom margins (`windowMargins`).
    static let margin: CGFloat = 20

    init(content: NSViewController, title: String) {
        let window = NSWindow(contentViewController: content)
        window.title = title
        Self.styleTitleBar(of: window)
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    /// Settings' title bar: the content runs under it, without its band or
    /// line, and an empty toolbar shows the title in bold.
    private static func styleTitleBar(of window: NSWindow) {
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        let toolbar = NSToolbar(identifier: "AutoHushWindow")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
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
    var floatsInCorner = false {
        didSet {
            guard let window else { return }
            window.level = floatsInCorner ? .floating : .normal
            if floatsInCorner { window.collectionBehavior.insert(.fullScreenAuxiliary) }
            watchTopEdge(floatsInCorner)
        }
    }

    /// The top edge kept while it floats; the user moving it moves it.
    private var pinnedTop: CGFloat?
    private var edgeObservers: [NSObjectProtocol] = []
    static let cornerMargin: CGFloat = 16

    /// A hosting controller for `view` that sizes the window to it.
    static func sizedToFit<Content: View>(_ view: Content) -> NSHostingController<Content> {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        return hosting
    }

    /// Shown and not closed since: on screen, or hidden with AutoHush (⌘H).
    var isOpen: Bool { window?.isOpen == true }

    func show() {
        guard let window else { return }
        if !window.isOpen {
            // Sized to its content first: centered at its first, empty size,
            // it would grow from the middle of the screen, partly off it.
            if let fitting = window.contentView?.fittingSize, fitting.width > 0, fitting.height > 0 {
                window.setContentSize(fitting)
            }
            if floatsInCorner {
                // On the screen the user is on: the one with the pointer.
                let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
                if let area = screen?.visibleFrame {
                    window.setFrameTopLeftPoint(NSPoint(x: area.maxX - window.frame.width - Self.cornerMargin,
                                                        y: area.maxY - Self.cornerMargin))
                }
                pinnedTop = window.frame.maxY
            } else {
                window.center()
            }
        }
        window.showInFront()
    }

    /// While it floats, a change of size keeps its top edge where it was, so
    /// it never grows off the top of the screen; a move by the user is kept.
    private func watchTopEdge(_ watch: Bool) {
        edgeObservers.forEach(NotificationCenter.default.removeObserver)
        edgeObservers = []
        guard watch, let window else { return }
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
        ]
    }

    /// Brings it in front of other apps' windows, on the desktop the user is
    /// on, without making it key: for while AutoHush's menu opens.
    func bringForward() {
        guard window?.isVisible == true else { return }
        window?.bringForward()
    }
}
