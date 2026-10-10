import AppKit
import SwiftUI

/// The Settings window, laid out as System Settings: a sidebar of pages, and
/// the page chosen beside it, its name in the toolbar. The user resizes it
/// within `minimumSize` and `maximumSize`: the sidebar keeps its width and
/// the page grows from 480 to 640 pt wide. It opens where and as big as it
/// was left, the first time at `initialSize`, centered.
@MainActor
final class SettingsWindowController: NSWindowController {
    /// The window's pages, in the sidebar's order.
    enum Page: CaseIterable, Hashable {
        case general, apps, detection, fades, diagnostics, updates, about

        /// The sidebar's groups of pages, a gap between each.
        static let groups: [[Page]] = [[.general, .apps], [.detection, .fades], [.diagnostics, .updates, .about]]

        var title: String {
            switch self {
            case .general:
                String(localized: "General", comment: "Settings: a page in the sidebar")
            case .apps:
                String(localized: "Apps", comment: "Settings: a page in the sidebar: which apps pause your player")
            case .detection:
                String(localized: "Detection", comment: "Settings: the page (and Diagnostics' heading) of when other apps count as playing or stopped")
            case .fades:
                String(localized: "Fades", comment: "Settings: the page of playback's fade out and fade in (in the sidebar: keep it short, about 16 characters); also, with a check, under the media player in Settings → General, and a Diagnostics row: whether AutoHush can fade the media player")
            case .diagnostics:
                String(localized: "Diagnostics", comment: "Settings: a page in the sidebar: what AutoHush sees right now")
            case .updates:
                String(localized: "Updates", comment: "Menu toolbar button, Settings page and Diagnostics row: AutoHush's updates")
            case .about:
                String(localized: "About", comment: "Menu: button at the bottom; shows About AutoHush")
            }
        }

        /// The page's symbol in the sidebar, on a square tinted with the
        /// accent color.
        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .apps: "square.grid.2x2.fill"
            case .detection: "waveform"
            case .fades: "speaker.wave.2.fill"
            case .diagnostics: "stethoscope"
            case .updates: "arrow.down.circle.fill"
            case .about: "info.circle.fill"
            }
        }
    }

    /// The sidebar's width, whatever the window's.
    static let sidebarWidth: CGFloat = 235
    /// The page between 480 and 640 pt wide; tall enough for the whole
    /// sidebar, foot included.
    static let minimumSize = NSSize(width: sidebarWidth + 480, height: 560)
    static let maximumSize = NSSize(width: sidebarWidth + 640, height: 900)
    static let initialSize = NSSize(width: 760, height: 620)
    /// Where macOS keeps the window's place and size between launches.
    static let frameName = "Settings"

    let model: SettingsModel
    private let navigation = SettingsNavigation()
    private let toolbarDelegate = SettingsToolbarDelegate()
    /// The window has a place: kept from a previous launch, or centered once.
    private var isPlaced: Bool

    init(model: SettingsModel) {
        self.model = model
        let split = SettingsSplitViewController()
        let sidebar = NSHostingController(rootView: SettingsSidebar(model: model, navigation: navigation))
        sidebar.sizingOptions = []
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth
        split.addSplitViewItem(sidebarItem)
        let page = NSHostingController(rootView: SettingsPageView(model: model, navigation: navigation))
        page.sizingOptions = []
        let pageItem = NSSplitViewItem(viewController: page)
        pageItem.titlebarSeparatorStyle = .none
        split.addSplitViewItem(pageItem)

        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: "Settings")
        toolbar.delegate = toolbarDelegate
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.contentMinSize = Self.minimumSize
        window.contentMaxSize = Self.maximumSize
        window.setContentSize(Self.initialSize)
        isPlaced = window.setFrameUsingName(Self.frameName)
        window.setFrameAutosaveName(Self.frameName)
        window.title = navigation.page.title
        super.init(window: window)
        navigation.onChange = { [weak window] page in window?.title = page.title }
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
    /// Apps' search is closed.
    func show(page: Page? = nil) {
        let reopening = window?.isOpen != true
        if reopening {
            model.foldedDiagnostics = []
            model.appSearch = nil
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

/// Which page Settings shows; the window's title follows it.
@MainActor
@Observable
final class SettingsNavigation {
    var page = SettingsWindowController.Page.general {
        didSet { if page != oldValue { onChange?(page) } }
    }
    @ObservationIgnored var onChange: ((SettingsWindowController.Page) -> Void)?
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

/// The page the sidebar points to.
struct SettingsPageView: View {
    let model: SettingsModel
    let navigation: SettingsNavigation

    var body: some View {
        Group {
            switch navigation.page {
            case .general: GeneralSettingsView(model: model)
            case .apps: AppsSettingsView(model: model)
            case .detection: DetectionSettingsView(model: model)
            case .fades: FadesSettingsView(model: model)
            case .diagnostics: DiagnosticsSettingsView(model: model)
            case .updates: UpdatesSettingsView(model: model)
            case .about: AboutSettingsView(model: model)
            }
        }
        .font(.appBody)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A Settings page's cards, as wide as the page and scrolling when the
/// window is shorter than they are.
struct SettingsPageScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
