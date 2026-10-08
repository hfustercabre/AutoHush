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
/// [Search]   (while unfolded, with 8 players or more; typing narrows them down)
/// ✓ [icon] Spotify · Apple Music · (one not installed, dimmed)   (while unfolded)
///   Safari Web Apps · [icon] YT Music …              (the web apps, if any)
///   ↻ Learn Controls Again… / YT Music               (once the chosen one's are learned)
///   ⊕ Add a Web App…                                 (makes a website one)
/// ╭────────────────────────────────────────────╮
/// │ Learning YT Music's Controls                │  (until AutoHush has learned
/// │ ✓ Play something in YT Music  ○ Pause it    │  the chosen web app's button)
/// ╰────────────────────────────────────────────╯
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
        /// Opens the "Add a Web App" window.
        var addWebApp: @MainActor () -> Void = {}
        /// Forgets the chosen player's learned controls and learns them again.
        var learnControlsAgain: @MainActor () -> Void = {}
        /// The menu is about to open: a last chance to bring `status` up to
        /// date (e.g. which players are installed) before it is built.
        var menuWillOpen: @MainActor () -> Void
        var setIgnored: @MainActor (AudioSource, Bool) -> Void
        var resolveWarning: @MainActor (Permission) -> Void
        /// Quits and opens AutoHush again, so macOS applies System Audio
        /// Recording (see `AppStatus.offersReopen`).
        var reopen: @MainActor () -> Void = {}
        /// AntiDot mode doesn't need Audio Recording: the way past its warning.
        var useAntiDotMode: @MainActor () -> Void = {}
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
    /// The card at the top, and the players unfolded under it, with their
    /// search when there are enough of them.
    private var cardItem: NSMenuItem?
    /// Under the card while AutoHush learns the chosen player's controls.
    private var learningItem: NSMenuItem?
    private var playerSearchItem: NSMenuItem?
    private var playerRows: [NSMenuItem] = []

    init(status: AppStatus = AppStatus(), actions: Actions) {
        self.status = status
        self.actions = actions
        model = StatusMenuModel(status: status)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        model.perform = { [weak self] in self?.perform($0) }
        menu.autoenablesItems = false
        menu.font = Self.rowFont
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

    /// The icon follows at once, and the custom views while the menu is open;
    /// the rows are rebuilt when it next opens, so none moves under the
    /// pointer. A closed menu's views aren't updated: `rebuild()` catches
    /// them up when it opens.
    private func render() {
        renderIcon()
        guard isMenuOpen else { return }
        model.status = status
        if let cardItem { fit(cardItem, changed: true) } // the status line may wrap anew
        if let learningItem { fit(learningItem, changed: true) } // a step ticked, or learning done
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
        model.playerSearch = ""
        playerSearchItem = nil
        playerRows = []
        menu.removeAllItems()

        let card = hostedItem("card", StatusCardView(model: model))
        cardItem = card
        menu.addItem(card)
        learningItem = status.learningHasPlayed == nil ? nil : hostedItem("learning", LearningCardView(model: model))
        if let learningItem { menu.addItem(learningItem) }
        if let warning = status.warning {
            menu.addItem(warningItem(for: warning))
            if warning == .systemAudioRecording {
                // Its title lines up with the warning's, after its symbol.
                let antiDot = item(PermissionText.useAntiDot, #selector(useAntiDotMode))
                antiDot.image = NSImage(size: menu.items.last?.image?.size ?? .zero)
                menu.addItem(antiDot)
            }
        }
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

    /// A row showing `view`, as wide as the menu; one that `takesKeyboard`
    /// gets what's typed while it shows.
    private func hostedItem<Content: View>(_ identifier: String, _ view: Content, takesKeyboard: Bool = false) -> NSMenuItem {
        let item = NSMenuItem()
        item.identifier = NSUserInterfaceItemIdentifier(identifier)
        let root = view.font(.appBody)
        let hosting = takesKeyboard ? KeyboardTakingHostingView(rootView: root) : NSHostingView(rootView: root)
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
        let item = status.offersReopen
            ? item(PermissionText.reopen, #selector(reopen))
            : item(warning.grantTitle, #selector(resolveWarning(_:)), payload: Payload(warning))
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
        submenu.font = Self.rowFont
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

    /// The rows the menu draws itself, a step above the system's menu font,
    /// like the custom views' text (`Font.appBody`).
    static let rowFont = NSFont.menuFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize + 1)

    // MARK: - The music players

    /// Unfolds the players under the card, or folds them back. They're the
    /// menu's own rows: a second menu can't open from inside an open one.
    /// From `PlayerOption.searchThreshold` players on, a search comes first.
    private func togglePlayerList() {
        if model.isChoosingPlayer {
            ([playerSearchItem].compactMap { $0 } + playerRows).forEach(menu.removeItem)
            playerSearchItem = nil
            playerRows = []
            model.playerSearch = ""
        } else if let cardItem {
            let options = status.playerOptions.offered
            var first = menu.index(of: cardItem) + 1
            if options.isSearchable {
                let search = hostedItem("playerSearch", PlayerSearchRow(model: model), takesKeyboard: true)
                menu.insertItem(search, at: first)
                playerSearchItem = search
                first += 1
            }
            showPlayerRows(options, at: first)
        }
        model.isChoosingPlayer.toggle()
    }

    /// Shows the unfolded players whose names match `search`.
    private func searchPlayers(_ search: String) {
        guard let playerSearchItem else { return } // folded meanwhile
        model.playerSearch = search
        playerRows.forEach(menu.removeItem)
        showPlayerRows(status.playerOptions.offered.matching(search), at: menu.index(of: playerSearchItem) + 1)
    }

    /// Inserts a row for each of `options` at `index`, with a heading over
    /// the Safari web apps, and "Add a Web App…" last; a note when there's
    /// none, because the search matched none. Before "Add a Web App…", once
    /// the chosen player's controls are learned (and nothing is searched
    /// for), the row that learns them again.
    private func showPlayerRows(_ options: [PlayerOption], at index: Int) {
        playerRows = options.map(playerRow)
        if let start = options.webAppsStart {
            playerRows.insert(.webAppsHeading(width: menuContentWidth), at: start)
        }
        if playerRows.isEmpty {
            let note = NSMenuItem(title: PlayerOption.noMatchNote(model.playerSearch), action: nil, keyEquivalent: "")
            note.isEnabled = false
            playerRows = [note]
        }
        if status.canLearnControlsAgain, model.playerSearch.isEmpty {
            let again = item(LearningText.learnAgainItem, #selector(learnControlsAgain))
            again.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            again.subtitle = status.playerName
            playerRows.append(again)
        }
        playerRows.append(addWebAppRow())
        for (offset, row) in playerRows.enumerated() { menu.insertItem(row, at: index + offset) }
    }

    /// Last under the players: makes a website a Safari web app.
    private func addWebAppRow() -> NSMenuItem {
        let row = item(PlayerOption.addWebAppTitle, #selector(addWebApp))
        row.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil)
        return row
    }

    /// A player to choose, checked when chosen. One that isn't installed
    /// can't be, and comes after those that are; a suggested web app opens
    /// "Add a Web App" filled in.
    private func playerRow(for option: PlayerOption) -> NSMenuItem {
        let row = item(option.name, #selector(chooseMusicPlayer(_:)), payload: Payload(option.bundleID))
        row.image = option.icon(size: 16)
        row.state = option.bundleID == status.chosenPlayerID ? .on : .off
        if option.isUntested {
            // The row's title starts about 37 pt in and ends 16 pt short of
            // the menu's edge.
            row.setTitle(option.name, badge: PlayerOption.untestedBadge, font: Self.rowFont, maxWidth: menuContentWidth - 56)
        }
        if !option.isInstalled {
            row.isEnabled = option.isClickable
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

    /// What the custom views ask for. Switches, the player list and its
    /// search act at once and keep the menu open; the rest close it first,
    /// as its rows do.
    func perform(_ command: StatusMenuCommand) {
        switch command {
        case .toggleAutoPause:
            actions.toggleAutoPause()
        case .setIgnored(let source, let ignored):
            actions.setIgnored(source, ignored)
        case .togglePlayerList:
            togglePlayerList()
        case .searchPlayers(let search):
            searchPlayers(search)
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
        case .toggleAutoPause, .setIgnored, .togglePlayerList, .searchPlayers, .retry: break // they act in perform(_:)
        }
    }

    @objc private func showAvailableUpdate() { actions.showAvailableUpdate() }

    @objc private func addWebApp() { actions.addWebApp() }

    @objc private func learnControlsAgain() { actions.learnControlsAgain() }

    @objc private func reopen() { actions.reopen() }

    @objc private func useAntiDotMode() { actions.useAntiDotMode() }

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

/// A menu row whose text field takes what's typed as soon as the row is in
/// the menu's window: SwiftUI's focus doesn't reach into an open menu, so
/// the field becomes AppKit's first responder instead.
private final class KeyboardTakingHostingView<Content: View>: NSHostingView<Content> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // Once SwiftUI has put its field in. The menu is tracking, so in the
        // run loop's common modes: the main queue waits until it closes.
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let field = editableTextField(in: self), window.makeFirstResponder(field) else { return }
                // The text it edits shows on the field's own background.
                (field.currentEditor() as? NSTextView)?.drawsBackground = false
            }
        }
    }
}

/// The first text field one can type into, in `view` or under it.
@MainActor
private func editableTextField(in view: NSView) -> NSTextField? {
    if let field = view as? NSTextField, field.isEditable { return field }
    return view.subviews.lazy.compactMap(editableTextField).first
}
