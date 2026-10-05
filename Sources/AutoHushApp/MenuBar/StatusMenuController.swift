import AppKit
import SwiftUI
import AutoHushKit

/// Owns the menu bar item and its menu, and renders an `AppStatus` into them.
///
/// ```text
/// ╭────────────────────────────────────────────╮
/// │ [icon] Spotify                         (●) │  the card: the player, what's
/// │        Paused — Safari is playing Auto-Pause │  happening, the Auto-Pause switch
/// │ ────────────────────────────────────────── │
/// │ Music player              [icon] Spotify ⌄ │  unfolds the players under it
/// ╰────────────────────────────────────────────╯
/// ✓ [icon] Spotify · Apple Music · (one not installed, dimmed)   (while unfolded)
/// ⚠ Allow Audio Recording Access…        (only when something needs fixing)
///   Turn off for
///   [5 min] [15 min] [30 min] [1 hr] [24 hr]
/// ─────────
///   Playing now
///   [icon] Safari   Pauses your music                  (●)
///   [icon] VLC      Ignored — music keeps playing      ( )
/// ─────────
///   Ignored Apps                  ▸ (click one to stop ignoring it)
/// ─────────
///   Install AutoHush 0.3.8…              (once one is found; Installing… while it installs)
///   [Settings]  [Updates]  [About]  [Quit]   (⌥-click Settings: Diagnostics)
/// ```
///
/// The card, the duration buttons, the playing apps and the toolbar are
/// SwiftUI views; they follow `status` even while the menu is open. The
/// rows around them are rebuilt each time it opens. AutoHush has no keyboard
/// shortcuts, standard ones included, unless the user asks for one.
@MainActor
final class StatusMenuController: NSObject {
    /// What the menu's items do; `AppDelegate` provides them.
    struct Actions {
        var toggleAutoPause: @MainActor () -> Void
        var snooze: @MainActor (AutoPauseSnooze) -> Void
        var chooseMusicPlayer: @MainActor (String) -> Void
        /// The menu is about to open: a last chance to bring `status` up to
        /// date (e.g. which players are installed) before it is built.
        var menuWillOpen: @MainActor () -> Void
        var setIgnored: @MainActor (AudioSource, Bool) -> Void
        var resolveWarning: @MainActor (Permission) -> Void
        var retry: @MainActor () -> Void
        var openSettings: @MainActor () -> Void
        var showDiagnostics: @MainActor () -> Void
        var showAvailableUpdate: @MainActor () -> Void
        var checkForUpdates: @MainActor () -> Void
        var showAbout: @MainActor () -> Void
        var quit: @MainActor () -> Void
    }

    /// Carries a menu item's argument to its action.
    private final class Payload<Value>: NSObject {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    /// The engine reports its state often (on every track change, for one),
    /// mostly without a change to show.
    var status: AppStatus {
        didSet { if status != oldValue { render() } }
    }

    let statusItem: NSStatusItem
    let menu = NSMenu()
    /// What the menu's custom views show.
    let model: StatusMenuModel

    private let actions: Actions
    private(set) var isMenuOpen = false
    /// The card at the top, and the players unfolded under it.
    private var cardItem: NSMenuItem?
    private var playerRows: [NSMenuItem] = []

    init(status: AppStatus = AppStatus(), actions: Actions) {
        self.status = status
        self.actions = actions
        model = StatusMenuModel(status: status)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        model.perform = { [weak self] in self?.perform($0) }
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        renderIcon()
        rebuild()
    }

    /// Removes the item from the menu bar (tests clean up with it).
    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Rendering

    /// The icon and the custom views follow at once; the rows are rebuilt
    /// when the menu next opens, so none moves under the pointer.
    private func render() {
        renderIcon()
        model.status = status
        if isMenuOpen, let cardItem { fit(cardItem, changed: true) } // the status line may wrap anew
    }

    private func renderIcon() {
        guard let button = statusItem.button else { return }
        button.image = status.icon.image(accessibilityDescription: status.iconAccessibilityLabel)
        button.title = ""
        button.imagePosition = .imageOnly
        button.appearsDisabled = status.dimsIcon
    }

    /// Puts the menu together for `status`.
    private func rebuild() {
        model.status = status
        model.listedSources = status.activeSources
        model.isChoosingPlayer = false
        playerRows = []
        menu.removeAllItems()

        let card = hostedItem("card", StatusCardView(model: model))
        cardItem = card
        menu.addItem(card)
        if let warning = status.warning { menu.addItem(warningItem(for: warning)) }
        menu.addItem(hostedItem("snooze", SnoozeBarView(model: model)))
        if !status.activeSources.isEmpty {
            menu.addItem(.separator())
            menu.addItem(hostedItem("playingApps", PlayingAppsView(model: model)))
        }
        if !status.ignoredApps.isEmpty {
            menu.addItem(.separator())
            menu.addItem(ignoredAppsItem())
        }
        menu.addItem(.separator())
        if let offer = status.updateOffer { menu.addItem(updateItem(for: offer)) }
        menu.addItem(hostedItem("toolbar", MenuToolbarView(model: model)))
    }

    /// A row showing `view`, as wide as the menu.
    private func hostedItem<Content: View>(_ identifier: String, _ view: Content) -> NSMenuItem {
        let item = NSMenuItem()
        item.identifier = NSUserInterfaceItemIdentifier(identifier)
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width]
        item.view = hosting
        fit(item)
        return item
    }

    /// Sizes a custom view's row to what it shows now.
    private func fit(_ item: NSMenuItem, changed: Bool = false) {
        guard let view = item.view else { return }
        view.layoutSubtreeIfNeeded() // applies what the model changed, or the size is the old one
        let size = NSSize(width: max(menuContentWidth, view.frame.width), height: view.fittingSize.height)
        guard view.frame.size != size else { return }
        view.frame.size = size
        if changed { menu.itemChanged(item) }
    }

    private func warningItem(for warning: Permission) -> NSMenuItem {
        let item = item(warning.grantTitle, #selector(resolveWarning(_:)), payload: Payload(warning))
        let description = String(localized: "Warning", comment: "VoiceOver label: this menu item needs attention")
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: description)
        return item
    }

    /// "Install AutoHush 0.3.8…", which shows the update found; while it
    /// installs, a greyed-out "Installing…".
    private func updateItem(for offer: UpdateOffer) -> NSMenuItem {
        let version = offer.release.version.description
        if offer.state == .installing {
            let title = String(localized: "Installing AutoHush \(version)…",
                               comment: "Menu item, greyed out while an update installs; %@ is its version")
            let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            row.isEnabled = false
            return row
        }
        let title = String(localized: "Install AutoHush \(version)…",
                           comment: "Menu item: shows the update found; %@ is its version")
        let item = item(title, #selector(showAvailableUpdate))
        let description = String(localized: "Update", comment: "VoiceOver label of the update icon")
        item.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: description)
        return item
    }

    private func ignoredAppsItem() -> NSMenuItem {
        let row = NSMenuItem(title: String(localized: "Ignored Apps", comment: "Menu item"), action: nil, keyEquivalent: "")
        row.image = NSImage(systemSymbolName: "speaker.slash", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let hintTitle = String(localized: "Click an app to stop ignoring it", comment: "Hint atop the Ignored Apps submenu")
        let hint = NSMenuItem(title: hintTitle, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        submenu.addItem(hint)
        for app in status.ignoredApps {
            let entry = item(app.name, #selector(toggleIgnored(_:)), payload: Payload((app, false)))
            entry.state = .on
            submenu.addItem(entry)
        }
        row.submenu = submenu
        return row
    }

    // MARK: - The music players

    /// Unfolds the players under the card, or folds them back. They're the
    /// menu's own rows: a second menu can't open from inside an open one.
    private func togglePlayerList() {
        if model.isChoosingPlayer {
            playerRows.forEach(menu.removeItem)
            playerRows = []
        } else if let cardItem {
            playerRows = status.playerOptions.map(playerRow)
            let first = menu.index(of: cardItem) + 1
            for (offset, row) in playerRows.enumerated() { menu.insertItem(row, at: first + offset) }
        }
        model.isChoosingPlayer.toggle()
    }

    /// A player to choose, checked when chosen. One that isn't installed
    /// can't be.
    private func playerRow(for option: PlayerOption) -> NSMenuItem {
        let row = item(option.name, #selector(chooseMusicPlayer(_:)), payload: Payload(option.bundleID))
        row.image = option.icon(size: 16)
        row.state = option.bundleID == status.chosenPlayerID ? .on : .off
        if !option.isInstalled {
            row.isEnabled = false
            row.subtitle = PlayerOption.notInstalledLabel
        }
        return row
    }

    private func item(_ title: String, _ action: Selector, payload: NSObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = payload
        return item
    }

    // MARK: - Actions

    /// What the custom views ask for. Switches and the player list act at
    /// once and keep the menu open; the rest close it first, as its rows do.
    func perform(_ command: StatusMenuCommand) {
        switch command {
        case .toggleAutoPause:
            actions.toggleAutoPause()
        case .setIgnored(let source, let ignored):
            actions.setIgnored(source, ignored)
        case .togglePlayerList:
            togglePlayerList()
        case .retry:
            actions.retry() // the card shows how it goes
        case .snooze, .openSettings, .showDiagnostics, .updates, .showAbout, .quit:
            menu.cancelTracking()
            // Once the menu has closed, as for its own rows.
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                MainActor.assumeIsolated { self?.run(command) }
            }
        }
    }

    private func run(_ command: StatusMenuCommand) {
        switch command {
        case .snooze(let snooze): actions.snooze(snooze)
        case .openSettings:       actions.openSettings()
        case .showDiagnostics:    actions.showDiagnostics()
        case .updates:            status.updateOffer == nil ? actions.checkForUpdates() : actions.showAvailableUpdate()
        case .showAbout:          actions.showAbout()
        case .quit:               actions.quit()
        case .toggleAutoPause, .setIgnored, .togglePlayerList, .retry: perform(command)
        }
    }

    @objc private func showAvailableUpdate() { actions.showAvailableUpdate() }

    @objc private func chooseMusicPlayer(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? Payload<String> else { return }
        actions.chooseMusicPlayer(payload.value)
    }

    @objc private func toggleIgnored(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? Payload<(AudioSource, Bool)> else { return }
        actions.setIgnored(payload.value.0, payload.value.1)
    }

    @objc private func resolveWarning(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? Payload<Permission> else { return }
        actions.resolveWarning(payload.value)
    }
}

// MARK: - NSMenuDelegate

extension StatusMenuController: NSMenuDelegate {
    /// Called before the menu opens, while it can still be rebuilt.
    func menuNeedsUpdate(_ menu: NSMenu) {
        actions.menuWillOpen()
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }
}
