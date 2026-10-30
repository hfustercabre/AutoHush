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
    /// The window's pages (`SettingsPage`), by the name they had here.
    typealias Page = SettingsPage

    /// The sidebar's width, whatever the window's.
    static let sidebarWidth: CGFloat = 235
    /// The page between 480 and 640 pt wide, wider when a choice needs it
    /// in the app's language (the user, 2026-10-17: "make the minimum width
    /// respect the content"); tall enough for the whole sidebar, foot
    /// included.
    /// At least 600 pt tall, so the sidebar shows About above its foot (S1, the user, 2026-10-18;
    /// 650 while Calls was a page, 2026-10-21, back to 600 with Behavior; it opens 620 tall).
    static var minimumSize: NSSize { NSSize(width: sidebarWidth + leastPageWidth, height: 600) }
    static var maximumSize: NSSize { NSSize(width: sidebarWidth + max(640, leastPageWidth), height: 900) }

    /// The page's least width: 480, or Fine-Tuning's AntiDot mode's ways
    /// (`ChoiceChips`) with the form's margins around them (20 pt to its box,
    /// 10 in it, a side). The update choice is a pop-up menu since A4 (2026-10-26).
    private static let leastPageWidth: CGFloat = {
        max(480, ChoiceChips<Never>.fittingWidth(DetectionMethod.antiDotWays.map(\.title)) + 2 * (20 + 10))
    }()
    static let initialSize = NSSize(width: 760, height: 620)
    /// Where macOS keeps the window's place and size between launches.
    static let frameName = "Settings"

    let model: SettingsModel
    private let navigation = SettingsNavigation()
    private let toolbarDelegate: SettingsToolbarDelegate
    /// The highlight the arrow keys and the pointer move, the sidebar's and the page's.
    let keys = SettingsKeys()

    /// `frameName`: where the window's place and size are kept; tests give
    /// each window a name of its own, since AppKit gives a name to one
    /// window at a time.
    init(model: SettingsModel, frameName: String = SettingsWindowController.frameName) {
        self.model = model
        toolbarDelegate = SettingsToolbarDelegate(navigation: navigation)
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
        // or the sidebar more height (600 from 2026-10-18).
        if let window, let content = window.contentView?.frame.size,
           content.width < Self.minimumSize.width || content.height < Self.minimumSize.height {
            window.setContentSize(NSSize(width: max(content.width, Self.minimumSize.width),
                                         height: max(content.height, Self.minimumSize.height)))
        }
        window?.title = navigation.page.title
        navigation.onChange = { [weak window = self.window, weak model, toolbarDelegate, keys] page in
            window?.title = page.title
            // A Behavior row's card in Fine-Tuning: only for that visit.
            if page != .fineTuning {
                model?.fineTuningFocus = nil
                model?.fineTuningFocusTakesHighlight = false
            }
            toolbarDelegate.updateArrows()
            // Back and Forward while the sidebar has the highlight: it follows the page.
            if keys.sidebar.highlighted != nil { keys.sidebar.highlightCurrent() }
        }
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
    /// menu's mapping), not while a field takes what's typed, nor in a sheet.
    func handleKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, windowNumber: Int) -> Bool {
        guard let window, windowNumber == window.windowNumber, window.attachedSheet == nil,
              !(window.firstResponder is NSText), // a search field's editor
              let key = HighlightKey(keyCode: keyCode, modifiers: flags) else { return false }
        // With keyboard navigation on, Tab may have given a control the focus.
        let controlHasFocus = NSApp.isFullKeyboardAccessEnabled && !(window.firstResponder is NSWindow)
        // One highlight at a time: the arrows take it from the focus.
        if key == .up || key == .down { window.makeFirstResponder(nil) }
        if keys.handle(key, controlHasFocus: controlHasFocus) { return true }
        // Delete removes the apps selected in Sound Sources, as their Remove
        // does (macOS's lists' key; the workflow audit, 2026-10-22).
        guard key == .delete, navigation.page == .soundSources, !model.appList.selectedApps.isEmpty else { return false }
        model.appList.removeSelected()
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
        }
        model.refreshLaunchAtLogin()
        model.refreshMenuBarIcon()
        placeOnce()
        window?.showInFront()
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
        String(localized: "Back", comment: "Welcome window: button that goes back to the list of media players. Also Settings: the toolbar's arrow and the View menu's item (⌘[) that show the page shown before; macOS's own word")
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

/// The split view without a line between the sidebar and the page: the
/// sidebar's own background sets it apart.
private final class SettingsSplitViewController: NSSplitViewController {
    override func loadView() {
        let view = ClearDividerSplitView()
        view.isVertical = true
        view.dividerStyle = .thin
        splitView = view
        super.loadView()
    }

    override func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool { true }
}

private final class ClearDividerSplitView: NSSplitView {
    override var dividerColor: NSColor { .clear }
}
