import AppKit
import SwiftUI
import AutoHushKit

/// The Settings window, laid out as System Settings: a sidebar of pages, and
/// the page chosen beside it, its name in the toolbar. The user resizes it
/// within `minimumSize` and `maximumSize`: the sidebar keeps its width and
/// the page grows from 480 to 640 pt wide. It opens where and as big as it
/// was left, the first time at `initialSize`, centered.
@MainActor
final class SettingsWindowController: NSWindowController {
    /// The window's pages, in the sidebar's order.
    enum Page: CaseIterable, Hashable {
        case general, mediaPlayer, soundSources, behavior, fineTuning, diagnostics, about

        /// The sidebar's groups of pages, a gap between each (B, the user's
        /// pick, 2026-10-21; W1, W2 and W3, 2026-10-25; memory
        /// `settings-layout`): since S5d + S5a (the user's pick, 2026-10-25)
        /// Everyday's pages and Advanced's, each named with what it's for,
        /// then About.
        static let groups: [Group] = [
            Group(title: Group.everydayTitle, note: Group.everydayNote, pages: [.general, .mediaPlayer, .soundSources, .behavior]),
            Group(title: Group.advancedTitle, note: Group.advancedNote, pages: [.fineTuning, .diagnostics]),
            Group(title: nil, note: nil, pages: [.about]),
        ]

        /// A group of the sidebar's pages, under its name and what it's for.
        struct Group {
            let title: String?
            let note: String?
            let pages: [Page]

            static var everydayTitle: String {
                String(localized: "Everyday", comment: "Settings' sidebar: the name over the pages most people use (General, Media Player, Sound Sources, Behavior)")
            }

            static var everydayNote: String {
                String(localized: "What most people change", comment: "Settings' sidebar, under “Everyday”: what its pages are for")
            }

            static var advancedTitle: String {
                String(localized: "Advanced", comment: "Settings' sidebar: the name over Fine-Tuning and Diagnostics, for people who want to adjust more or look closer")
            }

            static var advancedNote: String {
                String(localized: "Fine-tuning and checks", comment: "Settings' sidebar, under “Advanced”: what its pages are for (Fine-Tuning's settings, Diagnostics' checks)")
            }
        }

        var title: String {
            switch self {
            case .general:
                String(localized: "General", comment: "Settings: a page in the sidebar")
            case .mediaPlayer:
                PlayerOption.mediaPlayerHeading
            case .soundSources:
                String(localized: "Sound Sources", comment: "Settings: a page in the sidebar: the apps heard playing sound, each switched to pause your player or be ignored (keep it short, about 16 characters)")
            case .behavior:
                String(localized: "Behavior", comment: "Settings: a page in the sidebar: the switches for when your player pauses and resumes, the fades, the volume and AntiDot mode (keep it short, about 16 characters)")
            case .fineTuning:
                String(localized: "Fine-Tuning", comment: "Settings: a page in the sidebar, under Advanced: the timings, fade lengths, volume limits and detection that Behavior's switches use (keep it short, about 16 characters)")
            case .diagnostics:
                String(localized: "Diagnostics", comment: "Settings: a page in the sidebar: what AutoHush sees right now")
            case .about:
                String(localized: "About", comment: "Menu: button at the bottom; shows About AutoHush")
            }
        }

        /// The page's symbol in the sidebar, on a square tinted with the
        /// accent color.
        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .mediaPlayer: "music.note"
            case .soundSources: "square.grid.2x2.fill"
            case .behavior: "playpause.fill"
            case .fineTuning: "slider.horizontal.3"
            case .diagnostics: "stethoscope"
            case .about: "info.circle.fill"
            }
        }
    }

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

    /// The page's least width: 480, or the widest choice (`ChoiceChips`)
    /// with the form's margins around it (20 pt to its box, 10 in it, a side).
    private static let leastPageWidth: CGFloat = {
        let choices = [AutomaticUpdates.allCases.map(\.title),
                       DetectionMethod.antiDotWays.map(\.title)]
        return max(480, (choices.map { ChoiceChips<Never>.fittingWidth($0) }.max() ?? 0) + 2 * (20 + 10))
    }()
    static let initialSize = NSSize(width: 760, height: 620)
    /// Where macOS keeps the window's place and size between launches.
    static let frameName = "Settings"

    let model: SettingsModel
    private let navigation = SettingsNavigation()
    private let toolbarDelegate = SettingsToolbarDelegate()
    /// The highlight the arrow keys and the pointer move, the sidebar's and the page's.
    let keys = SettingsKeys()
    /// The window has a place: kept from a previous launch, or centered once.
    private var isPlaced: Bool

    /// `frameName`: where the window's place and size are kept; tests give
    /// each window a name of its own, since AppKit gives a name to one
    /// window at a time.
    init(model: SettingsModel, frameName: String = SettingsWindowController.frameName) {
        self.model = model
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

        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // Resizable, but never full screen, as no AutoHush window: the green
        // button zooms it within `maximumSize`.
        window.collectionBehavior.insert(.fullScreenNone)
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: "Settings")
        toolbar.delegate = toolbarDelegate
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        // Before Liquid Glass, the toolbar draws a lighter band of its own
        // over the page, under its name: see-through, the page runs up to
        // the top (checked on macOS 15.0.1).
        if #unavailable(macOS 26) { window.titlebarAppearsTransparent = true }
        window.contentMinSize = Self.minimumSize
        window.contentMaxSize = Self.maximumSize
        window.setContentSize(Self.initialSize)
        isPlaced = window.setFrameUsingName(frameName)
        // A size kept from before a choice needed more room, another language,
        // or the sidebar more height (600 from 2026-10-18).
        if let content = window.contentView?.frame.size,
           content.width < Self.minimumSize.width || content.height < Self.minimumSize.height {
            window.setContentSize(NSSize(width: max(content.width, Self.minimumSize.width),
                                         height: max(content.height, Self.minimumSize.height)))
        }
        window.title = navigation.page.title
        super.init(window: window)
        // On the controller, once it has the window: a controller gives the
        // window it gets its own name, on macOS 14 and 15 an empty one too,
        // which cleared the window's (it opened at its first place and size
        // at each launch).
        windowFrameAutosaveName = frameName
        navigation.onChange = { [weak window, weak model] page in
            window?.title = page.title
            // A Behavior row's card in Fine-Tuning: only for that visit.
            if page != .fineTuning { model?.fineTuningFocus = nil }
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
    var shownPage: Page? {
        window?.isOpen == true ? navigation.page : nil
    }

    /// Shows the window on `page` when given. Otherwise a window that was
    /// closed opens on General again, and one still open (minimized too)
    /// keeps its page. Reopened, Diagnostics has every part open again and
    /// Sound Sources' search is closed.
    func show(page: Page? = nil) {
        let reopening = window?.isOpen != true
        if reopening {
            model.foldedDiagnostics = []
            model.appList.search = nil
            keys.clear()
        }
        if let target = page ?? (reopening ? .general : nil) { navigation.page = target }
        model.refreshLaunchAtLogin()
        if !isPlaced {
            window?.center()
            isPlaced = true
        }
        window?.showInFront()
        // Nothing has the keyboard until the user asks: no focus ring on a page at first.
        if reopening { window?.makeFirstResponder(nil) }
    }
}

/// The toolbar over the page: only the line that keeps the page's name over
/// the page rather than over the sidebar.
private final class SettingsToolbarDelegate: NSObject, NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator]
    }

    /// No items of its own (macOS 14 logs the delegate as invalid without it).
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        nil
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
