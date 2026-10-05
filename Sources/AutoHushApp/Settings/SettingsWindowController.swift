import AppKit
import SwiftUI

/// The Settings window: General, Apps, Advanced and Diagnostics tabs in a
/// toolbar, the standard layout of macOS settings windows.
@MainActor
final class SettingsWindowController: NSWindowController {
    /// The window's tabs, in toolbar order.
    enum Tab: CaseIterable {
        case general, apps, advanced, diagnostics

        var title: String {
            switch self {
            case .general:  return String(localized: "General", comment: "Settings tab")
            case .apps:     return String(localized: "Apps", comment: "Settings tab: which apps pause the music")
            case .advanced: return String(localized: "Advanced", comment: "Settings tab")
            case .diagnostics:
                return String(localized: "Diagnostics", comment: "Settings tab: what AutoHush sees right now")
            }
        }

        var symbolName: String {
            switch self {
            case .general:  return "gearshape"
            case .apps:     return "square.grid.2x2"
            case .advanced: return "slider.horizontal.3"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    let model: SettingsModel
    private let tabController = SettingsTabViewController()

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
        }

        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The tab shown, when the window is on screen.
    var shownTab: Tab? {
        guard window?.isVisible == true, Tab.allCases.indices.contains(tabController.selectedTabViewItemIndex) else { return nil }
        return Tab.allCases[tabController.selectedTabViewItemIndex]
    }

    /// Shows the window, on `tab` when given.
    func show(tab: Tab? = nil) {
        if let tab, let index = Tab.allCases.firstIndex(of: tab) { tabController.selectedTabViewItemIndex = index }
        model.refreshLaunchAtLogin()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

/// Resizes the window as soon as the shown tab's content changes height, e.g.
/// when a switch shows or hides rows, keeping its top edge where it is.
/// NSTabViewController alone only hears of the change at the next event when
/// it comes from a click: the window kept its old size until then, and then
/// jumped.
final class SettingsTabViewController: NSTabViewController {
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
