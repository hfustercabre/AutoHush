import AppKit
import SwiftUI

/// The Settings window: General, Apps, Advanced, Diagnostics and About tabs
/// in a toolbar, the standard layout of macOS settings windows.
@MainActor
final class SettingsWindowController: NSWindowController {
    /// The window's tabs, in toolbar order.
    enum Tab: CaseIterable {
        case general, apps, advanced, diagnostics, about

        var title: String {
            switch self {
            case .general:  return String(localized: "General", comment: "Settings tab")
            case .apps:     return String(localized: "Apps", comment: "Settings tab: which apps pause the music")
            case .advanced: return String(localized: "Advanced", comment: "Settings tab")
            case .diagnostics:
                return String(localized: "Diagnostics", comment: "Settings tab: what AutoHush sees right now")
            case .about:    return String(localized: "About", comment: "Menu: button at the bottom; shows About AutoHush")
            }
        }

        var symbolName: String {
            switch self {
            case .general:  return "gearshape"
            case .apps:     return "square.grid.2x2"
            case .advanced: return "slider.horizontal.3"
            case .diagnostics: return "stethoscope"
            case .about:    return "info.circle"
            }
        }
    }

    let model: SettingsModel
    private let tabController = SettingsTabViewController()
    /// Advanced's content: Apps grows up to its height.
    private var advancedTab: NSViewController?

    init(model: SettingsModel) {
        self.model = model
        tabController.tabStyle = .toolbar
        for tab in Tab.allCases {
            let content: AnyView
            switch tab {
            case .general:  content = AnyView(GeneralSettingsView(model: model))
            case .apps:     content = AnyView(AppsSettingsView(model: model))
            case .advanced: content = AnyView(AdvancedSettingsView(model: model))
            case .diagnostics: content = AnyView(DiagnosticsSettingsView(model: model))
            case .about:    content = AnyView(AboutSettingsView(model: model))
            }
            // Tells the window to fit as soon as the tab's content changes height.
            let tabs = tabController
            let hosting = NSHostingController(rootView: AnyView(
                content
                    .font(.appBody)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { _ in tabs.contentHeightDidChange() }
            ))
            hosting.sizingOptions = .preferredContentSize
            hosting.title = tab.title // the window shows the selected tab's title
            let item = NSTabViewItem(viewController: hosting)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title)
            tabController.addTabViewItem(item)
            if tab == .advanced { advancedTab = hosting }
        }

        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        tabController.willShowTab = { [weak self] index in
            if Tab.allCases.firstIndex(of: .apps) == index { self?.measureAppsMaximumHeight() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The tab shown, when the window is on screen.
    var shownTab: Tab? {
        guard window?.isVisible == true, Tab.allCases.indices.contains(tabController.selectedTabViewItemIndex) else { return nil }
        return Tab.allCases[tabController.selectedTabViewItemIndex]
    }

    /// Shows the window on `tab` when given. Otherwise a window that was
    /// closed opens on General again, and one still open keeps its tab.
    /// Reopened, Diagnostics has every part open again and Apps' search is
    /// closed.
    func show(tab: Tab? = nil) {
        let reopening = window?.isVisible != true
        if reopening {
            model.foldedDiagnostics = []
            model.appSearch = nil
        }
        let target = tab ?? (reopening ? .general : nil)
        if let target, let index = Tab.allCases.firstIndex(of: target) { tabController.selectedTabViewItemIndex = index }
        model.refreshLaunchAtLogin()
        measureAppsMaximumHeight()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Apps may grow as tall as Advanced is now, in this language and with
    /// or without its fades note.
    private func measureAppsMaximumHeight() {
        guard let height = advancedTab?.view.fittingSize.height, height > 0 else { return }
        model.appsMaximumHeight = height
    }
}

/// Resizes the window as soon as the shown tab's content changes height, e.g.
/// when a switch shows or hides rows, keeping its top edge where it is.
/// NSTabViewController alone only hears of the change at the next event when
/// it comes from a click: the window kept its old size until then, and then
/// jumped.
final class SettingsTabViewController: NSTabViewController {
    /// Called with a tab's index just before it shows.
    var willShowTab: ((Int) -> Void)?

    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        if let tabViewItem { willShowTab?(tabView.indexOfTabViewItem(tabViewItem)) }
        super.tabView(tabView, willSelect: tabViewItem)
    }

    /// The shown tab's content changed height (SwiftUI reports it at once).
    func contentHeightDidChange() {
        // After the layout pass that changed it, when the tab's
        // preferredContentSize has caught up.
        DispatchQueue.main.async { MainActor.assumeIsolated { self.fitWindowToShownTab() } }
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        guard viewController !== shownTab else { return fitWindowToShownTab() }
        super.preferredContentSizeDidChange(for: viewController)
    }

    private var shownTab: NSViewController? {
        tabViewItems.indices.contains(selectedTabViewItemIndex) ? tabViewItems[selectedTabViewItemIndex].viewController : nil
    }

    private func fitWindowToShownTab() {
        guard let tab = shownTab, let window = view.window, let content = window.contentView else { return }
        let change = tab.preferredContentSize.height - content.frame.height
        guard tab.preferredContentSize.height > 0, change != 0 else { return }
        var frame = window.frame
        frame.size.height += change
        frame.origin.y -= change // the top stays put
        if let visible = window.screen?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = visible.minY // grow upwards rather than off the bottom of the screen
        }
        window.setFrame(frame, display: true)
    }
}
