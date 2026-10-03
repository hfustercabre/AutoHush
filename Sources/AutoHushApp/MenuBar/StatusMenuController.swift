import AppKit
import AutoHushKit

/// Owns the menu bar item and its menu, and renders an `AppStatus` into them.
///
/// ```text
/// Music paused — Google Chrome is playing
/// ─────────
/// [icon] Google Chrome            ▸ Never Pause Music for Google Chrome
/// [icon] VLC  (Ignored)           ▸ ✓ Never Pause Music for VLC
/// ─────────
/// ✓ Auto-Pause Music
///   Turn Off For                  ▸ 5 · 15 · 30 Minutes · 1 Hour · 24 Hours
///   Ignored Apps                  ▸ (click one to stop ignoring it)
/// ─────────
/// ⚠ Allow Audio Recording Access…    (only when something needs fixing)
///   Retry                         ⌘R (only after a failed start)
///   Update Available: 0.3.0…         (only when a newer release exists)
///   Settings…                     ⌘,   (⌥: Diagnostics…)
/// ─────────
///   About AutoHush
///   Check for Updates…
///   Quit AutoHush             ⌘Q
/// ```
@MainActor
final class StatusMenuController: NSObject {
    /// What the menu's items do; `AppDelegate` provides them.
    struct Actions {
        var toggleAutoPause: @MainActor () -> Void
        var snooze: @MainActor (AutoPauseSnooze) -> Void
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

    var status: AppStatus {
        didSet { render() }
    }

    let statusItem: NSStatusItem
    let menu = NSMenu()

    private let actions: Actions
    private let statusBar: NSStatusBar
    /// While the menu is open only the icon and status line follow `status`;
    /// the rest is rebuilt when it closes, so an open submenu never collapses.
    private(set) var isMenuOpen = false
    private var needsRebuild = false

    init(status: AppStatus = AppStatus(), actions: Actions, statusBar: NSStatusBar = .system) {
        self.status = status
        self.actions = actions
        self.statusBar = statusBar
        self.statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        render()
    }

    /// Removes the item from the menu bar.
    func remove() {
        statusBar.removeStatusItem(statusItem)
    }

    // MARK: - Rendering

    private func render() {
        renderIcon()
        if isMenuOpen {
            menu.items.first?.title = status.statusLine
            needsRebuild = true
            return
        }
        needsRebuild = false
        menu.removeAllItems()
        addStatusLine()
        addPlayingApps()
        addAutoPauseItems()
        addActionItems()
        addAppItems()
    }

    /// The status line, always the first item: it alone follows `status`
    /// while the menu is open.
    private func addStatusLine() {
        let statusLine = NSMenuItem(title: status.statusLine, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
    }

    /// One row per app playing right now.
    private func addPlayingApps() {
        guard !status.activeSources.isEmpty else { return }
        menu.addItem(.separator())
        status.activeSources.forEach { menu.addItem(sourceItem(for: $0)) }
    }

    /// Auto-Pause Music, Turn Off For and, when there are any, Ignored Apps.
    private func addAutoPauseItems() {
        menu.addItem(.separator())
        menu.addItem(autoPauseItem())
        menu.addItem(snoozeItem())
        if !status.ignoredApps.isEmpty { menu.addItem(ignoredAppsItem()) }
    }

    /// Whatever needs attention (a permission, Retry, an update), then Settings.
    private func addActionItems() {
        menu.addItem(.separator())
        if let warning = status.warning { menu.addItem(warningItem(for: warning)) }
        if status.showsRetry {
            let title = String(localized: "Retry", comment: "Menu item: start monitoring again after a problem")
            menu.addItem(item(title, #selector(retry), key: "r"))
        }
        if let update = status.availableUpdate { menu.addItem(updateItem(for: update)) }
        menu.addItem(item(String(localized: "Settings…", comment: "Menu item"), #selector(openSettings), key: ","))
        menu.addItem(diagnosticsItem())
    }

    /// About, Check for Updates and Quit.
    private func addAppItems() {
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "About AutoHush", comment: "Menu item"), #selector(showAbout)))
        menu.addItem(item(String(localized: "Check for Updates…", comment: "Menu item"), #selector(checkForUpdates)))
        menu.addItem(item(String(localized: "Quit AutoHush", comment: "Menu item"), #selector(quit), key: "q"))
    }

    private func renderIcon() {
        guard let button = statusItem.button else { return }
        button.image = status.icon.image(accessibilityDescription: status.iconAccessibilityLabel)
        button.title = ""
        button.imagePosition = .imageOnly
        button.appearsDisabled = status.dimsIcon
    }

    private func sourceItem(for source: AudioSource) -> NSMenuItem {
        let isIgnored = status.isIgnored(source.id)
        let row = NSMenuItem(title: source.name, action: nil, keyEquivalent: "")
        row.image = AppIcon.image(for: source)
        if isIgnored {
            row.subtitle = String(localized: "Ignored — music keeps playing",
                                  comment: "Under an app in the menu that never pauses the music")
        }

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let toggle = item(
            String(localized: "Never Pause Music for \(source.name)", comment: "Menu item; %@ is an app"),
            #selector(toggleIgnored(_:)),
            payload: Payload((source, !isIgnored))
        )
        toggle.state = isIgnored ? .on : .off
        submenu.addItem(toggle)
        row.submenu = submenu
        return row
    }

    private func warningItem(for warning: Permission) -> NSMenuItem {
        let item = item(warning.grantTitle, #selector(resolveWarning(_:)), payload: Payload(warning))
        let description = String(localized: "Warning", comment: "VoiceOver label: this menu item needs attention")
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: description)
        return item
    }

    private func updateItem(for update: AppRelease) -> NSMenuItem {
        let title = String(localized: "Update Available: \(update.version.description)…",
                           comment: "Menu item; %@ is a version number")
        let item = item(title, #selector(showAvailableUpdate))
        let description = String(localized: "Update", comment: "VoiceOver label of the update icon")
        item.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: description)
        return item
    }

    /// Takes the place of Settings… while ⌥ is held.
    private func diagnosticsItem() -> NSMenuItem {
        let title = String(localized: "Diagnostics…", comment: "Menu item, shown while ⌥ is held")
        let item = item(title, #selector(showDiagnostics), key: ",")
        item.keyEquivalentModifierMask = [.command, .option]
        item.isAlternate = true
        return item
    }

    private func autoPauseItem() -> NSMenuItem {
        let title = String(localized: "Auto-Pause Music", comment: "Menu item and Settings switch")
        let item = item(title, #selector(toggleAutoPause))
        item.state = status.autoPause == .on ? .on : .off
        return item
    }

    private func snoozeItem() -> NSMenuItem {
        let title = String(localized: "Turn Off For",
                           comment: "Menu item; its submenu offers 5, 15 and 30 Minutes, 1 Hour and 24 Hours")
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for snooze in AutoPauseSnooze.allCases {
            submenu.addItem(item(snooze.title, #selector(snooze(_:)), payload: Payload(snooze)))
        }
        row.submenu = submenu
        return row
    }

    private func ignoredAppsItem() -> NSMenuItem {
        let row = NSMenuItem(title: String(localized: "Ignored Apps", comment: "Menu item"), action: nil, keyEquivalent: "")
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

    private func item(_ title: String, _ action: Selector, key: String = "", payload: NSObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.representedObject = payload
        return item
    }

    // MARK: - Actions

    @objc private func toggleAutoPause() { actions.toggleAutoPause() }
    @objc private func retry() { actions.retry() }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func showDiagnostics() { actions.showDiagnostics() }
    @objc private func showAvailableUpdate() { actions.showAvailableUpdate() }
    @objc private func checkForUpdates() { actions.checkForUpdates() }
    @objc private func showAbout() { actions.showAbout() }
    @objc private func quit() { actions.quit() }

    @objc private func snooze(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? Payload<AutoPauseSnooze> else { return }
        actions.snooze(payload.value)
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
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        if needsRebuild { render() }
    }
}
