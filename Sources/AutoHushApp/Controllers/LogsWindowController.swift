import AppKit
import SwiftUI

/// AutoHush's logs, from Settings → Diagnostics' Show Logs…: a window the
/// user resizes (never full screen), which opens where and as big as it
/// was left, the first time centered. It follows new lines while it's open.
@MainActor
final class LogsWindowController: PlacedWindowController, NSWindowDelegate {
    static let minimumSize = NSSize(width: 760, height: 440)
    static let initialSize = NSSize(width: 960, height: 640)
    /// Where macOS keeps the window's place and size between launches (a
    /// new name with the bigger size, so the old, smaller one isn't kept).
    static let frameName = "Logs Window"

    let model: LogsModel
    /// Page Up, Page Down, Home and End, while the window is open.
    private var keyMonitor: Any?

    /// `frameName`: where the window's place and size are kept; tests give
    /// each window a name of its own, as Settings' do.
    init(model: LogsModel, frameName: String = LogsWindowController.frameName) {
        self.model = model
        let hosting = NSHostingController(rootView: LogsView(model: model))
        hosting.sizingOptions = []
        // As AutoHush's other windows: the title bar part of the window, its title in bold.
        super.init(content: hosting, frameName: frameName, minimumSize: Self.minimumSize, initialSize: Self.initialSize,
                   toolbar: NSToolbar(identifier: "AutoHushLogs"))
        window?.title = Self.title
        window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static var title: String {
        String(localized: "AutoHush Logs",
               comment: "Title of the window that shows what AutoHush logged (opened from Settings → Diagnostics), and the name of the file its Save… writes")
    }

    func show() {
        // Shown again while open (or minimized): the search stays.
        if window?.isOpen != true { model.open() }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let keyCode = event.keyCode, flags = event.modifierFlags, windowNumber = event.windowNumber
                let handled = MainActor.assumeIsolated {
                    self?.scrollEntries(keyCode: keyCode, flags: flags, windowNumber: windowNumber) == true
                }
                return handled ? nil : event
            }
        }
        placeOnce()
        window?.showInFront()
    }

    func windowWillClose(_ notification: Notification) {
        model.close()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Page Up and Page Down scroll the entries a page, Home and End to the
    /// oldest and the newest, wherever the keyboard is, the search
    /// included, where they do nothing (KB7, the a11y audit, 2026-11-06:
    /// older entries could be read only with the mouse). `false` leaves the
    /// key to the window.
    func scrollEntries(keyCode: UInt16, flags: NSEvent.ModifierFlags, windowNumber: Int) -> Bool {
        guard let window, windowNumber == window.windowNumber, window.attachedSheet == nil,
              let key = HighlightKey(keyCode: keyCode, modifiers: flags),
              let scrollView = window.contentView.flatMap(Self.entries(in:)),
              let document = scrollView.documentView else { return false }
        let clip = scrollView.contentView
        let visible = clip.documentVisibleRect
        let range = max(0, document.frame.height - visible.height)
        // From the top, whichever way the document's coordinates go.
        let fromTop = document.isFlipped ? visible.minY : range - visible.minY
        let page = max(visible.height - scrollView.verticalPageScroll, visible.height / 2)
        let target: CGFloat
        switch key {
        case .pageUp: target = fromTop - page
        case .pageDown: target = fromTop + page
        case .home: target = 0
        case .end: target = range
        default: return false
        }
        let clamped = min(max(target, 0), range)
        clip.scroll(to: NSPoint(x: visible.minX, y: document.isFlipped ? clamped : range - clamped))
        scrollView.reflectScrolledClipView(clip)
        return true
    }

    /// The entries' scroll view: the window's tallest.
    private static func entries(in view: NSView) -> NSScrollView? {
        var found: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView { found.append(scroll) }
            view.subviews.forEach(walk)
        }
        walk(view)
        return found.max { $0.frame.height < $1.frame.height }
    }
}
