import AppKit

/// The toolbar over the page: the line that keeps the page's name over the
/// page rather than over the sidebar, and Back and Forward before it.
@MainActor
final class SettingsToolbarDelegate: NSObject, NSToolbarDelegate {
    static let history = NSToolbarItem.Identifier("history")

    private let navigation: SettingsNavigation
    private weak var arrows: NSToolbarItemGroup?

    init(navigation: SettingsNavigation) {
        self.navigation = navigation
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, Self.history]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, Self.history]
    }

    /// Back and Forward, as System Settings has them (the user, 2026-10-25):
    /// two arrows joined, before the page's name, each dimmed with nothing
    /// to go to.
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.history else { return nil }
        let back = SettingsWindowController.backTitle, forward = SettingsWindowController.forwardTitle
        let group = NSToolbarItemGroup(itemIdentifier: itemIdentifier,
                                       images: [NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: back),
                                                NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: forward)]
                                           .compactMap { $0 },
                                       selectionMode: .momentary, labels: [back, forward],
                                       target: self, action: #selector(walk(_:)))
        group.controlRepresentation = .expanded
        group.isNavigational = true
        group.autovalidates = false
        for (item, tip) in zip(group.subitems, [back, forward]) {
            item.autovalidates = false
            item.toolTip = tip
        }
        arrows = group
        update(group)
        return group
    }

    func updateArrows() {
        if let arrows { update(arrows) }
    }

    private func update(_ group: NSToolbarItemGroup) {
        guard group.subitems.count == 2 else { return }
        group.subitems[0].isEnabled = navigation.canGoBack
        group.subitems[1].isEnabled = navigation.canGoForward
    }

    /// The arrow clicked: the group's segment, 0 for Back.
    @objc private func walk(_ sender: NSToolbarItemGroup) {
        if sender.selectedIndex == 0 { navigation.goBack() } else { navigation.goForward() }
    }
}
