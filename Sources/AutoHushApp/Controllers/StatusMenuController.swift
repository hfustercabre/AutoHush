import AppKit
import SwiftUI
import AutoHushKit

/// Owns the menu bar item and its menu, and renders an `AppStatus` into them.
///
/// ```text
/// ╭────────────────────────────────────────────────╮
/// │ [icon] Spotify                             (●) │  the card: the player, what's
/// │        Paused — Safari is playing   Auto-Pause │  happening, the Auto-Pause switch;
/// │        [Retry] · [Reopen] · [Unmute]           │  a chip when one helps (below)
/// │ ────────────────────────────────────────────── │
/// │ Media player                  [icon] Spotify ⌄ │  unfolds the players under it
/// │ ────────────────────────────────────────────── │
/// │ Controls                     [Learn Controls…] │  (a web app: whether its
/// │ Not learned yet: …                             │  controls are learned)
/// ╰────────────────────────────────────────────────╯
/// [Search]   (while unfolded, with 8 players or more; typing narrows them down)
///   Supported Apps                                   (while unfolded)
/// ✓ [icon] Spotify · Apple Music · (one not installed, dimmed)
///   Other Apps  Checked by you · [icon] Deezer …     (the apps added through a check)
///   ⊕ Add an App…                                    (checks an app and adds it)
///   Safari Web Apps · [icon] YT Music …              (the web apps, if any)
///   ⊕ Add a Web App…                                 (makes a website one)
/// ⚠ Allow Audio Recording Access…        (only when something needs fixing)
///   Turn off for
///   [5 min] [15 min] [30 min] [1 hr] [24 hr]
/// ─────────
///   Playing Now
///   [icon] Safari   Pauses your player                 (●)
///   [icon] VLC      Ignored — your player keeps playing ( )
///   Recently Played                  (the apps that played in the last 5 minutes)
///   [icon] Messages Pauses your player                 (●)
/// ─────────
///   Ignored Apps                  ▸ (click one to stop ignoring it)
/// ─────────
///   Detection · Fades · Advanced   (More Settings: folded at first)
///   ⌄                               (shows or folds them)
/// ─────────
///   Install AutoHush 0.3.8…              (once one is found; Installing… while it installs)
///   [Settings]  [Updates]  [About]  [Quit]   (⌥-click Settings: Diagnostics)
/// ```
///
/// The card's chips: Retry after a failed start, Reopen while the player
/// needs reopening (an app added through a check), Unmute while a player
/// that can only be muted is muted for another app.
///
/// The card, the duration buttons, the playing apps and the toolbar are
/// SwiftUI views; they follow `status` even while the menu is open, as
/// Ignored Apps does. The other rows are rebuilt each time it opens. Its rows have no keyboard
/// shortcuts: AutoHush has none of its own (its menu bar, while a window is
/// open, has the Mac's standard ones: `MainMenu`).
@MainActor
final class StatusMenuController: NSObject {
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

    /// What the menu's items do: the user's settings, Retry, the updates,
    /// and what only AppDelegate does.
    private let settings: UserSettings
    private let session: PlayerSession
    private let updates: any UpdateCommands
    private weak var actions: (any AppActions)?
    private(set) var isMenuOpen = false
    /// The card at the top, and the players unfolded under it, with their
    /// search when there are enough of them.
    private var cardItem: NSMenuItem?
    /// The search over the unfolded players, while it shows.
    private var playerSearchItem: NSMenuItem?
    private var playerRows: [NSMenuItem] = []
    /// Ignored Apps and the separator above it, hidden while no app is
    /// ignored. Unlike the other rows, they follow the ignored apps while the
    /// menu is open (the user, 2026-10-16): a switch under Playing Now
    /// changes them at once.
    private var ignoredAppsRows: (separator: NSMenuItem, row: NSMenuItem)?
    /// Detection's, Fades' and Advanced's settings, as Settings changes them.
    private let settingsModel: SettingsModel?
    /// More Settings' rows, in order, the chevron last.
    private var moreSettingsRows: [(row: MoreSettingsRow, item: NSMenuItem)] = []
    /// Shows or hides its rows one after the other while it unfolds or folds.
    private var moreSettingsAnimation: Timer?
    /// How long it unfolds or folds: briefly, while the menu shows.
    static let moreSettingsDuration: TimeInterval = 0.15

    init(status: AppStatus = AppStatus(), settings: UserSettings, session: PlayerSession,
         updates: any UpdateCommands, actions: (any AppActions)?, settingsModel: SettingsModel? = nil) {
        self.status = status
        self.settings = settings
        self.settingsModel = settingsModel
        self.session = session
        self.updates = updates
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
        showIgnoredApps()
    }

    private func renderIcon() {
        guard let button = statusItem.button else { return }
        button.image = status.icon.image(accessibilityDescription: status.iconAccessibilityLabel, showsUpdate: status.iconShowsUpdate)
        // The badged image is as tall as the item: drawn as it is, not scaled to fit.
        button.imageScaling = .scaleNone
        button.title = ""
        button.imagePosition = .imageOnly
        button.appearsDisabled = status.dimsIcon
    }

    /// Puts the menu together for `status`.
    private func rebuild() {
        model.status = status
        model.listedSources = status.activeSources
        model.listedRecentSources = status.recentSources()
        model.isChoosingPlayer = false
        model.playerSearch = ""
        model.announcesRetryOutcome = false
        playerSearchItem = nil
        playerRows = []
        menu.removeAllItems()

        let card = hostedItem("card", StatusCardView(model: model))
        cardItem = card
        menu.addItem(card)
        if let warning = status.warning {
            menu.addItem(warningItem(for: warning))
            // Not for a player that can only be muted: AntiDot mode can't mute it.
            if warning == .systemAudioRecording, !status.playerNeedsLevels {
                // Its title lines up with the warning's, after its symbol.
                let antiDot = item(PermissionText.useAntiDot, #selector(useAntiDotMode))
                antiDot.shownImage = NSImage(size: menu.items.last?.image?.size ?? .zero)
                menu.addItem(antiDot)
            }
        }
        menu.addItem(hostedItem("snooze", SnoozeBarView(model: model)))
        if !model.listedSources.isEmpty || !model.listedRecentSources.isEmpty {
            menu.addItem(.separator())
        }
        if !model.listedSources.isEmpty {
            menu.addItem(hostedItem("playingApps", PlayingAppsView(model: model, list: .playingNow)))
        }
        if !model.listedRecentSources.isEmpty {
            menu.addItem(hostedItem("recentApps", PlayingAppsView(model: model, list: .recentlyPlayed)))
        }
        let ignoredApps = (separator: NSMenuItem.separator(), row: ignoredAppsItem())
        menu.addItem(ignoredApps.separator)
        menu.addItem(ignoredApps.row)
        ignoredAppsRows = ignoredApps
        showIgnoredApps()
        if let settingsModel {
            menu.addItem(.separator())
            moreSettingsAnimation?.invalidate()
            moreSettingsAnimation = nil
            moreSettingsRows = MoreSettingsRow.allCases.map { row in
                let item = hostedItem("moreSettings.\(row.rawValue)", MoreSettingsRowView(row: row, model: model, settings: settingsModel))
                menu.addItem(item)
                return (row, item)
            }
            showMoreSettings()
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
        item.shownImage = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: description)
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
        item.shownImage = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: description)
        return item
    }

    private func ignoredAppsItem() -> NSMenuItem {
        let row = NSMenuItem(title: String(localized: "Ignored Apps", comment: "Menu item"), action: nil, keyEquivalent: "")
        row.shownImage = NSImage(systemSymbolName: "speaker.slash", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.font = Self.rowFont
        row.submenu = submenu
        return row
    }

    /// Lists the ignored apps under Ignored Apps, shown while there's one.
    private func showIgnoredApps() {
        guard let (separator, row) = ignoredAppsRows, let submenu = row.submenu else { return }
        let apps = status.ignoredApps
        separator.isHidden = apps.isEmpty
        row.isHidden = apps.isEmpty
        let shown = submenu.items.dropFirst().compactMap { ($0.representedObject as? Payload<(AudioSource, Bool)>)?.value.0 }
        guard shown != apps else { return }
        submenu.removeAllItems()
        let hintTitle = String(localized: "Click an app to stop ignoring it", comment: "Hint atop the Ignored Apps submenu")
        let hint = NSMenuItem(title: hintTitle, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        submenu.addItem(hint)
        for app in apps {
            let entry = item(app.name, #selector(toggleIgnored(_:)), payload: Payload((app, false)))
            entry.state = .on
            submenu.addItem(entry)
        }
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
            let options = offeredPlayers
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
        showPlayerRows(offeredPlayers.matching(search), at: menu.index(of: playerSearchItem) + 1)
    }

    /// The players as the menu offers them: in AntiDot mode, the apps that
    /// can only be muted can't be chosen.
    private var offeredPlayers: [PlayerOption] {
        status.playerOptions.inAntiDotMode(settings.state.detection != .audioLevels).offered
    }

    /// Inserts a row for each of `options` at `index`: the supported apps
    /// under their heading; the apps added through a check under theirs,
    /// then "Add an App…" (E3); the Safari web apps under theirs, and "Add a
    /// Web App…" last. A note first when the search matched none.
    private func showPlayerRows(_ options: [PlayerOption], at index: Int) {
        let apps = options.filter { $0.kind == .app }
        let checked = options.filter { $0.kind == .checkedApp }
        let webApps = options.filter { $0.kind == .safariWebApp }
        var rows: [NSMenuItem] = []
        if options.isEmpty {
            let note = NSMenuItem(title: PlayerOption.noMatchNote(model.playerSearch), action: nil, keyEquivalent: "")
            note.isEnabled = false
            rows.append(note)
        }
        if !apps.isEmpty { rows += [.supportedAppsHeading(width: menuContentWidth)] + apps.map(playerRow) }
        // While a search narrows the players, the heading shows only over a match.
        if !checked.isEmpty || model.playerSearch.isEmpty { rows.append(.otherAppsHeading(width: menuContentWidth, isEmpty: checked.isEmpty)) }
        rows += checked.flatMap { [playerRow(for: $0), removeRow(for: $0)] } + [addRow(PlayerOption.addAppTitle, #selector(addApp))]
        if !webApps.isEmpty { rows += [.webAppsHeading(width: menuContentWidth)] + webApps.map(playerRow) }
        rows.append(addRow(PlayerOption.addWebAppTitle, #selector(addWebApp)))
        playerRows = rows
        for (offset, row) in playerRows.enumerated() { menu.insertItem(row, at: index + offset) }
    }

    /// "Add an App…" after the apps added through a check; "Add a Web App…"
    /// last under the players.
    private func addRow(_ title: String, _ action: Selector) -> NSMenuItem {
        let row = item(title, action)
        row.shownImage = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil)
        return row
    }

    /// A player to choose, checked when chosen. One that isn't installed
    /// can't be, and comes after those that are; a suggested web app opens
    /// "Add a Web App" filled in. In AntiDot mode, an app that can only be
    /// muted can't be either, and says why (still checked when chosen: the
    /// card says it can't be controlled).
    private func playerRow(for option: PlayerOption) -> NSMenuItem {
        let row = item(option.name, #selector(choosePlayer(_:)), payload: Payload(option.bundleID))
        row.shownImage = option.icon(size: 16)
        row.state = option.bundleID == status.chosenPlayerID ? .on : .off
        if option.isUntested {
            // The row's title starts about 37 pt in and ends 16 pt short of
            // the menu's edge.
            row.setTitle(option.name, badge: PlayerOption.untestedBadge, font: Self.rowFont, maxWidth: menuContentWidth - 56)
        }
        row.isEnabled = option.isClickable
        if !option.isInstalled {
            row.subtitle = option.webAddress != nil ? PlayerOption.clickToAddLabel : PlayerOption.notInstalledLabel
        } else if option.isUnavailableInAntiDotMode {
            row.subtitle = PlayerOption.antiDotModeLabel
            row.toolTip = option.antiDotModeReason
            row.setAccessibilityHelp(option.antiDotModeReason)
        } else if option.pausesByMuting {
            row.subtitle = PlayerOption.mutedInsteadLabel
        }
        // VoiceOver can't see an icon's badge: a Safari web app named as an
        // app is says so, as a Chromium browser's web app says whose it is.
        let spoken = option.spokenName(among: status.playerOptions)
        if spoken != option.name || option.isUntested {
            row.setAccessibilityLabel(option.isUntested ? "\(spoken), \(PlayerOption.untestedBadge)" : spoken)
        }
        return row
    }

    /// An added app's row while Option is held: removes it, after asking
    /// (R5, the user's pick, 2026-10-15; macOS's alternate menu items).
    private func removeRow(for option: PlayerOption) -> NSMenuItem {
        let row = item(PlayerOption.removeTitle(option.name), #selector(removeAddedApp(_:)), payload: Payload(option.bundleID))
        row.shownImage = option.icon(size: 16)
        row.isAlternate = true
        row.keyEquivalentModifierMask = .option
        return row
    }

    private func item(_ title: String, _ action: Selector, payload: NSObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = payload
        return item
    }

    /// Shows the rows of More Settings that apply now (all hidden but the
    /// chevron while it's folded). Rows are shown or hidden whole: the menu
    /// follows that while it's open, unlike a row changing its height.
    private func showMoreSettings() {
        guard let settingsModel, moreSettingsAnimation == nil else { return }
        for (row, item) in moreSettingsRows {
            item.isHidden = row != .chevron && !(model.showsMoreSettings && row.applies(settingsModel))
        }
    }

    /// Unfolds or folds More Settings: at once while the menu is closed
    /// (or with Reduce Motion on), else its rows show one after the other
    /// from the top, or hide from the bottom, over `moreSettingsDuration`.
    private func toggleMoreSettings() {
        moreSettingsAnimation?.invalidate()
        moreSettingsAnimation = nil
        model.showsMoreSettings.toggle()
        guard let settingsModel, isMenuOpen, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return showMoreSettings()
        }
        let unfolding = model.showsMoreSettings
        var steps = moreSettingsRows.filter { $0.row != .chevron && $0.row.applies(settingsModel) }.map(\.item)
        if !unfolding { steps.reverse() }
        guard !steps.isEmpty else { return showMoreSettings() }
        let interval = Self.moreSettingsDuration / Double(steps.count)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.showNextMoreSettingsRow() }
        }
        pendingMoreSettingsRows = (steps, unfolding)
        RunLoop.main.add(timer, forMode: .common) // runs while the menu tracks the pointer
        moreSettingsAnimation = timer
        showNextMoreSettingsRow()
    }

    /// The rows still to show or hide while More Settings unfolds or folds.
    private var pendingMoreSettingsRows: (items: [NSMenuItem], showing: Bool) = ([], true)

    private func showNextMoreSettingsRow() {
        guard !pendingMoreSettingsRows.items.isEmpty else {
            moreSettingsAnimation?.invalidate()
            moreSettingsAnimation = nil
            return showMoreSettings() // as the settings are now
        }
        let item = pendingMoreSettingsRows.items.removeFirst()
        item.isHidden = !pendingMoreSettingsRows.showing
    }

    // MARK: - Actions

    /// What the custom views ask for. Switches, the player list and its
    /// search act at once and keep the menu open; the rest close it first,
    /// as its rows do.
    func perform(_ command: StatusMenuCommand) {
        switch command {
        case .toggleAutoPause:
            settings.toggleAutoPause()
        case .setIgnored(let source, let ignored):
            settings.setIgnored(source, ignored)
        case .togglePlayerList:
            togglePlayerList()
        case .searchPlayers(let search):
            searchPlayers(search)
        case .toggleMoreSettings:
            toggleMoreSettings()
        case .updateMoreSettings:
            // After the click that changed them: hiding rows while the menu
            // handles it crops the menu's top (2026-10-17).
            RunLoop.main.perform(inModes: [.common]) { [weak self] in
                MainActor.assumeIsolated { self?.showMoreSettings() }
            }
        case .retry:
            model.announcesRetryOutcome = true
            session.retry() // the card shows how it goes
        case .updates where status.updateOffer == nil:
            // The menu stays open, its button saying "Checking…", until the
            // result: its alert closes the menu first (`closeMenu`).
            guard !model.isCheckingForUpdates else { return }
            model.isCheckingForUpdates = true
            Task { [weak self] in
                await self?.updates.checkNow()
                self?.model.isCheckingForUpdates = false
            }
        case .snooze, .openSettings, .showDiagnostics, .updates, .showAbout, .showControlError, .learnControls, .reopenPlayer,
             .unmutePlayer, .quit:
            menu.cancelTracking()
            // Once the menu has closed, as for its own rows.
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                MainActor.assumeIsolated { self?.run(command) }
            }
        }
    }

    private func run(_ command: StatusMenuCommand) {
        switch command {
        case .snooze(let snooze): settings.snooze(snooze)
        case .openSettings:       actions?.openSettings(page: nil)
        case .showDiagnostics:    actions?.openSettings(page: .diagnostics)
        case .updates:            updates.presentAvailableUpdate() // checking keeps the menu open: `perform`
        case .showAbout:          actions?.openSettings(page: .about)
        case .showControlError:   actions?.showControlError()
        case .learnControls:      actions?.learnControlsAgain()
        case .reopenPlayer:       actions?.reopenPlayer()
        case .unmutePlayer:       actions?.unmutePlayer()
        case .quit:               actions?.quit()
        case .toggleAutoPause, .setIgnored, .togglePlayerList, .searchPlayers, .retry, .toggleMoreSettings, .updateMoreSettings:
            break // they act in perform(_:)
        }
    }

    /// Closes the menu if it's open, and returns once it has: an alert, such
    /// as an update check's result, can't show over it.
    func closeMenu() async {
        guard isMenuOpen else { return }
        menu.cancelTracking()
        let deadline = ContinuousClock.now + .seconds(1)
        while isMenuOpen, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @objc private func showAvailableUpdate() { updates.presentAvailableUpdate() }

    @objc private func addWebApp() { actions?.openAddWebApp() }
    @objc private func addApp() { actions?.openAddApp() }

    @objc private func reopen() { actions?.reopenAutoHush() }

    @objc private func useAntiDotMode() { settings.setDetectionMethod(.playbackSignals) }

    @objc private func removeAddedApp(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? Payload<String> else { return }
        actions?.removeAddedApp(payload.value)
    }

    @objc private func choosePlayer(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? Payload<String> else { return }
        actions?.choosePlayer(payload.value)
    }

    @objc private func toggleIgnored(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? Payload<(AudioSource, Bool)> else { return }
        settings.setIgnored(payload.value.0, payload.value.1)
    }

    @objc private func resolveWarning(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? Payload<Permission> else { return }
        actions?.requestPermission(payload.value)
    }
}

// MARK: - NSMenuDelegate

extension StatusMenuController: NSMenuDelegate {
    /// Called before the menu opens, while it can still be rebuilt.
    func menuNeedsUpdate(_ menu: NSMenu) {
        actions?.menuWillOpen()
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        moreSettingsAnimation?.invalidate() // ended where it was going
        moreSettingsAnimation = nil
        showMoreSettings()
    }
}

/// A menu row whose text field takes what's typed as soon as the row is in
/// the menu's window: SwiftUI's focus doesn't reach into an open menu, so
/// the field becomes AppKit's first responder instead.
private final class KeyboardTakingHostingView<Content: View>: NSHostingView<Content> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // Once SwiftUI has put its field in: on the run loop's next turn, in
        // its common modes, which include the open menu's tracking.
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let field = self.firstEditableTextField, window.makeFirstResponder(field) else { return }
                // The text it edits shows on the field's own background.
                (field.currentEditor() as? NSTextView)?.drawsBackground = false
            }
        }
    }
}

private extension NSMenuItem {
    /// Its image, always shown: from macOS 27, AppKit hides menu items'
    /// images in apps built with its SDK unless an item asks to show its own.
    var shownImage: NSImage? {
        get { image }
        set {
            image = newValue
            if #available(macOS 27, *) { preferredImageVisibility = .visible }
        }
    }
}
