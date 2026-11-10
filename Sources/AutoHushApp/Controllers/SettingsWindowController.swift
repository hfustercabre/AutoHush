import AppKit
import SwiftUI
import AutoHushKit

/// The Settings window, laid out as System Settings: a sidebar of pages, and
/// the page chosen beside it, its name in the toolbar. The user resizes it
/// within `minimumSize` and `maximumSize`: the sidebar keeps its width and
/// the page grows from 480 to 640 pt wide. It opens where and as big as it
/// was left, the first time at `initialSize`, centered.
@MainActor
final class SettingsWindowController: PlacedWindowController {
    /// The sidebar's width, whatever the window's.
    static let sidebarWidth: CGFloat = 235
    /// The page between 480 and 640 pt wide, wider when a choice needs it
    /// in the app's language (the user, 2026-10-17: "make the minimum width
    /// respect the content"); tall enough for the whole sidebar, foot
    /// included.
    /// At least 650 pt tall, so the sidebar shows About above its foot (S1, the user, 2026-10-18;
    /// 650 while Calls was a page, 2026-10-21, back to 600 with Behavior) and About's page fits
    /// in its usual states (the user, 2026-10-31: "Raise the min height to 650").
    static var minimumSize: NSSize { NSSize(width: sidebarWidth + leastPageWidth, height: 650) }
    static var maximumSize: NSSize { NSSize(width: sidebarWidth + max(640, leastPageWidth), height: 900) }

    /// The page's least width: 480, or Fine-Tuning's AntiDot mode's ways
    /// (`ChoiceChips`) with the form's margins around them (20 pt to its box,
    /// 10 in it, a side). The update choice is a pop-up menu since A4 (2026-10-26).
    private static let leastPageWidth: CGFloat = {
        max(480, ChoiceChips<Never>.fittingWidth(DetectionMethod.antiDotWays.map(\.title)) + 2 * (20 + 10))
    }()
    static let initialSize = NSSize(width: 760, height: 650)
    /// Where macOS keeps the window's place and size between launches.
    static let frameName = "Settings"

    let model: SettingsModel
    private let navigation = SettingsNavigation()
    private let toolbarDelegate: SettingsToolbarDelegate
    /// The highlight the arrow keys and the pointer move, the sidebar's and the page's.
    let keys = SettingsKeys()
    /// macOS's keyboard navigation setting, read at each key (tests set it).
    var fullKeyboardAccess: @MainActor () -> Bool = { NSApp.isFullKeyboardAccessEnabled }
    /// The page's view, where its controls' frames are (`KeyHighlight.Control.frame`).
    private weak var pageView: NSView?
    /// Back and Forward as stops of the page's highlight (R2).
    let toolbarKeys: SettingsToolbarKeys

    /// `frameName`: where the window's place and size are kept; tests give
    /// each window a name of its own, since AppKit gives a name to one
    /// window at a time.
    /// Watches the window's first responder (a field taking the keyboard).
    private var responderWatch: NSKeyValueObservation?

    init(model: SettingsModel, frameName: String = SettingsWindowController.frameName) {
        self.model = model
        toolbarDelegate = SettingsToolbarDelegate(navigation: navigation)
        toolbarKeys = SettingsToolbarKeys(highlight: keys.page, goBack: { [navigation] in navigation.goBack() },
                                          goForward: { [navigation] in navigation.goForward() },
                                          canGo: { [navigation] in (navigation.canGoBack, navigation.canGoForward) })
        let split = SettingsSplitViewController()
        let sidebar = NSHostingController(rootView: SettingsSidebar(model: model, navigation: navigation).environment(keys.sidebar))
        sidebar.sizingOptions = []
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth
        split.addSplitViewItem(sidebarItem)
        let page = NSHostingController(rootView: SettingsPageView(model: model, navigation: navigation).environment(keys.page))
        page.sizingOptions = []
        let pageItem = NSSplitViewItem(viewController: page)
        pageItem.titlebarSeparatorStyle = .none
        split.addSplitViewItem(pageItem)

        let toolbar = NSToolbar(identifier: "Settings")
        toolbar.delegate = toolbarDelegate
        // Before Liquid Glass, the toolbar draws a lighter band of its own
        // over the page, under its name: see-through, the page runs up to
        // the top (checked on macOS 15.0.1).
        let seeThrough: Bool
        if #unavailable(macOS 26) { seeThrough = true } else { seeThrough = false }
        super.init(content: split, frameName: frameName, minimumSize: Self.minimumSize, maximumSize: Self.maximumSize,
                   initialSize: Self.initialSize, toolbar: toolbar, transparentTitleBar: seeThrough)
        // A size kept from before a choice needed more room, another language,
        // or more height (600 from 2026-10-18, 650 from 2026-10-31: 1.2.7 opened at 620).
        if let window, let content = window.contentView?.frame.size,
           content.width < Self.minimumSize.width || content.height < Self.minimumSize.height {
            window.setContentSize(NSSize(width: max(content.width, Self.minimumSize.width),
                                         height: max(content.height, Self.minimumSize.height)))
        }
        window?.title = navigation.page.title
        // The window's Undo and Redo (the Edit menu, ⌘Z and ⇧⌘Z): Restore
        // Defaults, Sound Sources' removals and what's typed in the search
        // (U10a, the user's pick, 2026-11-02), on the window's own undo
        // manager, which it keeps: emptied as it closes.
        window?.delegate = self
        model.undoManager = window?.undoManager
        model.appList.undoManager = window?.undoManager
        // Zoom follows the keys' highlight on each side (A3).
        keys.sidebar.screenFrame = { [weak view = sidebar.view] rect in view.flatMap { ZoomFocus.screenRect(of: rect, in: $0) } }
        keys.page.screenFrame = { [weak view = page.view] rect in view.flatMap { ZoomFocus.screenRect(of: rect, in: $0) } }
        pageView = page.view
        toolbarKeys.attach(to: window, pageView: page.view)
        navigation.onChange = { [weak window = self.window, weak model, toolbarDelegate, toolbarKeys, keys] page in
            window?.title = page.title
            // A Behavior row's card in Fine-Tuning: only for that visit.
            if page != .fineTuning {
                model?.fineTuningFocus = nil
                model?.fineTuningFocusTakesHighlight = false
            }
            toolbarDelegate.updateArrows()
            toolbarKeys.updateEnabled()
            // Back and Forward while the keys have the sidebar's highlight: it follows the page.
            keys.pageChanged()
        }
        // A field taking the keyboard (Sound Sources' search, by ⌘F, a
        // click or a key) lets go of the keys' highlight, on either side: the
        // caret is where the keys are now, one focus at a time (the a11y
        // audit's live check, 2026-11-06: the sidebar row stayed outlined).
        responderWatch = window?.observe(\.firstResponder, options: [.new]) { [keys] window, _ in
            MainActor.assumeIsolated {
                if window.firstResponder is NSText, keys.isLit { keys.clear() }
            }
        }
        keys.dropFocus = { [weak window = self.window] in _ = window?.makeFirstResponder(nil) }
        // Tab comes round to Sound Sources' search while it's open, after Back and Forward (K3).
        keys.focusSearch = { [weak self] in self?.focusPageSearch() ?? false }
        // → on a sidebar row Tab stopped on: into its page once it shows (R3).
        keys.showsFirstOfNextPage = { [weak model] in model?.shownPageTakesHighlight = true }
        // Before the focused control: the arrows move the highlight, as in
        // the menu. Kept for the controller's life, which is AutoHush's.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode, flags = event.modifierFlags, windowNumber = event.windowNumber
            let handled = MainActor.assumeIsolated {
                self?.handleKey(keyCode, flags: flags, windowNumber: windowNumber) == true
            }
            return handled ? nil : event
        }
    }

    /// The window's keys, as `SettingsKeys` takes them (`HighlightKey`, the
    /// menu's mapping), not in a sheet nor while an input method composes
    /// (`WindowKeyPress`); in a field, what's typed stays there
    /// (`handleKeyInField`).
    func handleKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, windowNumber: Int) -> Bool {
        guard let window, let press = WindowKeyPress(keyCode, flags: flags, windowNumber: windowNumber, in: window,
                                                     fullKeyboardAccess: fullKeyboardAccess) else { return false }
        // Escape closes Sound Sources' search, as its ✕ does, from the field
        // or from the rows the keys went on to (N4, 2026-11-06: nothing took it).
        if press.isEscape, navigation.page == .soundSources, model.appList.search != nil {
            model.appList.search = nil
            window.makeFirstResponder(nil)
            return true
        }
        // A search field's editor.
        if press.focus == .textField { return handleKeyInField(press, in: window) }
        guard let key = press.key else { return false }
        // One highlight at a time: the arrows (Tab and Page Up…End too) take it from
        // the focus, once they've moved on from it (`SettingsKeys.dropFocus`), and a
        // lit one, whose tint hides the focus's, gets the other keys too (N6, 2026-11-06).
        let moves = [.up, .down, .tab, .backTab].contains(key) || key.jump != nil
        if !moves, keys.isLit { window.makeFirstResponder(nil) }
        // Back and Forward where the toolbar has them now, and their ring after.
        toolbarKeys.updateFrames()
        defer { toolbarKeys.refresh() }
        if keys.handle(key, controlHasFocus: press.focus == .control) { return true }
        // Delete removes the apps selected in Sound Sources, as their Remove
        // does (macOS's lists' key; the workflow audit, 2026-10-22).
        guard key == .delete, navigation.page == .soundSources, !model.appList.selectedApps.isEmpty else { return false }
        model.appList.removeSelected()
        return true
    }

    /// A key while a field takes what's typed (Sound Sources' search):
    /// ↓ leaves it for the rows under it, the first one lit; Tab and
    /// Shift-Tab for the stops after it and before it in Tab's loop, in
    /// reading order: its ✕, beside it, and Forward or Back, over the page,
    /// else the sidebar's last (K3, 2026-11-10; the user's order, 2026-11-10:
    /// R1 had Tab go up to Back); ↑ stays in it (the search is the top);
    /// the rest is the field's (N4, 2026-11-06: with keyboard navigation
    /// off, the keys couldn't reach the rows it found).
    private func handleKeyInField(_ press: WindowKeyPress, in window: NSWindow) -> Bool {
        if press.key == .backTab || press.key == .tab {
            window.makeFirstResponder(nil)
            // Back and Forward where the toolbar has them now, and their ring after.
            toolbarKeys.updateFrames()
            defer { toolbarKeys.refresh() }
            if press.key == .tab { keys.tabFromSearch() } else { keys.backTabFromSearch() }
            return true
        }
        guard press.key == .down, let field = (window.firstResponder as? NSText)?.delegate as? NSView, let pageView,
              field.isDescendant(of: pageView) else { return false }
        let frame = pageView.convert(field.bounds, from: field)
        let foot = pageView.isFlipped ? frame.maxY : pageView.bounds.height - frame.minY
        window.makeFirstResponder(nil)
        keys.page.highlightFirst(below: foot)
        return true
    }

    /// The page's search (Sound Sources', while open) takes the keyboard, the
    /// caret after its text; `false` when none shows.
    func focusPageSearch() -> Bool {
        guard let window, let field = pageView?.firstEditableTextField, window.makeFirstResponder(field) else { return false }
        field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        return true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The page shown, when the window is open (on screen or minimized).
    var shownPage: SettingsPage? {
        window?.isOpen == true ? navigation.page : nil
    }

    /// Shows the window on `page` when given. Otherwise a window that was
    /// closed opens on General again, and one still open (minimized too)
    /// keeps its page. Reopened, Diagnostics has every part open again and
    /// Sound Sources' search is closed.
    func show(page: SettingsPage? = nil) {
        let reopening = window?.isOpen != true
        if reopening {
            model.foldedDiagnostics = []
            model.appList.search = nil
            keys.clear()
        }
        if let target = page ?? (reopening ? .general : nil) { navigation.page = target }
        // Opened afresh, nothing to go back to.
        if reopening {
            navigation.clearHistory()
            toolbarDelegate.updateArrows()
            toolbarKeys.updateEnabled()
        }
        model.refreshLaunchAtLogin()
        model.refreshMenuBarIcon()
        placeOnce()
        window?.showInFront()
        toolbarKeys.updateFrames() // laid out now
        // Nothing has the keyboard until the user asks: no focus ring on a page at first.
        if reopening { window?.makeFirstResponder(nil) }
    }

    // MARK: - Back and Forward

    /// The page shown before (the toolbar's ‹, ⌘[ in the View menu, sent
    /// along the responder chain).
    @objc func goBack(_ sender: Any?) { navigation.goBack() }

    /// The page left by Back (›, ⌘]).
    @objc func goForward(_ sender: Any?) { navigation.goForward() }

    var canGoBack: Bool { navigation.canGoBack }
    var canGoForward: Bool { navigation.canGoForward }

    /// Back's and Forward's names: the toolbar's arrows and the View menu.
    static var backTitle: String {
        ButtonText.back
    }

    static var forwardTitle: String {
        String(localized: "Forward", comment: "Settings: the toolbar's arrow and the View menu's item (⌘]) that show the page left by Back again; macOS's own word")
    }
}

extension SettingsWindowController: NSMenuItemValidation {
    /// Back and Forward dimmed with nothing to go to.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(goBack(_:)): canGoBack
        case #selector(goForward(_:)): canGoForward
        default: true
        }
    }
}

extension SettingsWindowController: NSWindowDelegate {
    /// The window is kept when closed: an Undo days later would undo a step
    /// long forgotten.
    func windowWillClose(_ notification: Notification) {
        window?.undoManager?.removeAllActions()
        toolbarKeys.removeRing()
    }
}
