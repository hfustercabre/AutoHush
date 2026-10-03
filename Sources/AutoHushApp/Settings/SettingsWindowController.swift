import AppKit
import SwiftUI

/// The Settings window: General, Apps and Advanced tabs in a toolbar, the
/// standard layout of macOS settings windows.
@MainActor
final class SettingsWindowController: NSWindowController {
    /// The window's tabs, in toolbar order.
    enum Tab: Int, CaseIterable {
        case general, apps, advanced

        var title: String {
            switch self {
            case .general:  return "General"
            case .apps:     return "Apps"
            case .advanced: return "Advanced"
            }
        }

        var symbolName: String {
            switch self {
            case .general:  return "gearshape"
            case .apps:     return "square.grid.2x2"
            case .advanced: return "slider.horizontal.3"
            }
        }
    }

    let model: SettingsModel
    private let tabController = NSTabViewController()

    init(model: SettingsModel) {
        self.model = model
        tabController.tabStyle = .toolbar
        for tab in Tab.allCases {
            let content: AnyView
            switch tab {
            case .general:  content = AnyView(GeneralSettingsView(model: model))
            case .apps:     content = AnyView(AppsSettingsView(model: model))
            case .advanced: content = AnyView(AdvancedSettingsView(model: model))
            }
            let hosting = NSHostingController(rootView: content)
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

    var selectedTab: Tab {
        Tab(rawValue: tabController.selectedTabViewItemIndex) ?? .general
    }

    func show(_ tab: Tab? = nil) {
        if let tab { tabController.selectedTabViewItemIndex = tab.rawValue }
        model.refreshLaunchAtLogin()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
