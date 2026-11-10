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
    /// The highlight the keys and the pointer move through its controls and
    /// its entries, as in Settings (R6, the user, 2026-11-10: reach every
    /// control, whatever macOS's keyboard navigation setting): Return
    /// presses the lit control, there being no main button.
    let keys = WindowKeys()
    /// macOS's keyboard navigation setting, read at each key (tests set it).
    var fullKeyboardAccess: @MainActor () -> Bool = { NSApp.isFullKeyboardAccessEnabled }
    /// The keys, while the window is open.
    private var keyMonitor: Any?

    /// The window the entries scroll in, for the view's ↑ and ↓ on them
    /// (`LogsView.scrollEntries`), once there's one.
    @MainActor private final class EntriesWindow {
        weak var window: NSWindow?
    }

    /// `frameName`: where the window's place and size are kept; tests give
    /// each window a name of its own, as Settings' do.
    init(model: LogsModel, frameName: String = LogsWindowController.frameName) {
        self.model = model
        let entriesWindow = EntriesWindow()
        let hosting = NSHostingController(rootView: LogsView(model: model) { step in
            entriesWindow.window.map { Self.scrollEntries(in: $0, step > 0 ? .down : .up) } ?? false
        }.environment(keys.highlight))
        hosting.sizingOptions = []
        // As AutoHush's other windows: the title bar part of the window, its title in bold.
        super.init(content: hosting, frameName: frameName, minimumSize: Self.minimumSize, initialSize: Self.initialSize,
                   toolbar: NSToolbar(identifier: "AutoHushLogs"))
        entriesWindow.window = window
        window?.title = Self.title
        window?.delegate = self
        keys.returnPresses = true
        keys.dropFocus = { [weak self] in _ = self?.window?.makeFirstResponder(nil) }
        // Its search is one of Tab's stops, as a guiding window's (K3).
        keys.focusSearch = { [weak self] in
            guard let window = self?.window, let field = window.contentView?.firstEditableTextField,
                  window.makeFirstResponder(field) else { return false }
            field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
            return true
        }
        // Zoom follows the keys' highlight (A3).
        keys.highlight.screenFrame = { [weak self] rect in
            self?.window?.contentView.flatMap { ZoomFocus.screenRect(of: rect, in: $0) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static var title: String {
        String(localized: "AutoHush Logs",
               comment: "Title of the window that shows what AutoHush logged (opened from Settings → Diagnostics), and the name of the file its Save… writes")
    }

    func show() {
        // Shown again while open (or minimized): the search stays.
        if window?.isOpen != true {
            model.open()
            keys.highlight.clear() // nothing lit as it opens
        }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let keyCode = event.keyCode, flags = event.modifierFlags, windowNumber = event.windowNumber
                let handled = MainActor.assumeIsolated {
                    self?.handleKey(keyCode, flags: flags, windowNumber: windowNumber) == true
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

    /// The window's keys: Page Up and Page Down scroll the entries
    /// (`scrollEntries`), wherever the keyboard is; the others move the
    /// highlight, as `WindowKeys` takes them (`HighlightKey`), not in a
    /// sheet nor while an input method composes (`WindowKeyPress`); in the
    /// search, ↓ and Tab leave it for the first control, Shift-Tab for the
    /// last, and Tab past the last control or Shift-Tab before the first
    /// come back into it (K3, 2026-11-10), as in the other windows; the
    /// rest stays the search's. `false` leaves the key to the window.
    func handleKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, windowNumber: Int) -> Bool {
        if scrollEntries(keyCode: keyCode, flags: flags, windowNumber: windowNumber) { return true }
        guard let window, let press = WindowKeyPress(keyCode, flags: flags, windowNumber: windowNumber, in: window,
                                                     fullKeyboardAccess: fullKeyboardAccess), let key = press.key else { return false }
        return keys.handle(key, focus: press.focus)
    }

    /// Page Up and Page Down scroll the entries a page, Home and End to the
    /// oldest and the newest, wherever the keyboard is, the search
    /// included, where they do nothing (KB7, the a11y audit, 2026-11-06:
    /// older entries could be read only with the mouse). `false` leaves the
    /// key to the window.
    func scrollEntries(keyCode: UInt16, flags: NSEvent.ModifierFlags, windowNumber: Int) -> Bool {
        guard let window, windowNumber == window.windowNumber, window.attachedSheet == nil,
              let key = HighlightKey(keyCode: keyCode, modifiers: flags), key.jump != nil else { return false }
        return Self.scrollEntries(in: window, key)
    }

    /// The entries scrolled for `key` (`ScrollKeys`); `false` at that end.
    private static func scrollEntries(in window: NSWindow, _ key: HighlightKey) -> Bool {
        guard let scrollView = window.contentView.flatMap(entries(in:)) else { return false }
        return ScrollKeys.scroll(scrollView, key)
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
