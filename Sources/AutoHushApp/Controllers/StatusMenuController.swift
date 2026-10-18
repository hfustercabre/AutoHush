import AppKit
import SwiftUI
import AutoHushKit

/// Owns the menu bar item and the menu it opens, and renders an `AppStatus`
/// into them. The menu is AutoHush's own panel (`MenuPanel`, the user's
/// choice, 2026-10-17), so its parts fold and unfold smoothly:
///
/// ```text
/// ╭────────────────────────────────────────────────╮
/// │ [icon] Spotify                             (●) │  the card (pinned): the player,
/// │        Paused — Safari is playing   Auto-Pause │  what's happening, the Auto-Pause
/// │        ✓ Automation allowed  ✓ Fades           │  switch, what AutoHush can do with
/// │        [Retry] · [Reopen] · [Unmute]           │  it, a chip when one helps;
/// │ Controls                     [Learn Controls…] │  a web app's controls
/// ╰────────────────────────────────────────────────╯
///  ♪ Media player               [icon] Spotify ⌄   unfolds the players under it:
///    [Search] · Supported Apps · Other Apps ·       a line between their groups;
///    Add an App… · Safari Web Apps · Add a Web App… ↑ ↓ and Return choose one
///  ⚠ Allow Audio Recording Access…        (only when something needs fixing)
///  Turn off for  [5 min] [15 min] [30 min] [1 hr] [24 hr]
///  ─────  Playing Now · Recently Played  (each app with its switch)
///  ─────  Ignored Apps                 1 ⌄  (folds out: click one to stop ignoring it)
///  ─────  Detection   AntiDot mode       (each page's switches always, under its
///                     ⌄                   name; an arrow unfolds the rest of a
///  ─────  Fades       Fade playback       part in its place: F3)
///                     ⌄
///  ─────  Advanced    Level the volume · Stay paused after calls
///  ─────  Install AutoHush 0.3.8…        (once one is found)
///  [Settings]  [Updates]  [About]  [Quit]   (pinned; ⌥-click Settings: Diagnostics)
/// ```
///
/// The menu follows `status` while it's open, but the apps listed under
/// Playing Now and Recently Played are fixed then, so no row moves under the
/// pointer. Only what's between the card and the buttons scrolls, the last
/// rows fading while more is below. It closes on a click outside it, on
/// Escape, when the desktop changes, as another window becomes key, and
/// before anything opens a window. It has no keyboard shortcuts: AutoHush
/// has none of its own.
@MainActor
final class StatusMenuController: NSObject {
    /// The engine reports its state often (on every track change, for one),
    /// mostly without a change to show.
    var status: AppStatus {
        didSet { if status != oldValue { render() } }
    }

    let statusItem: NSStatusItem
    /// What the menu shows.
    let model: StatusMenuModel
    /// The menu's window, made the first time it opens.
    private(set) var panel: MenuPanel?
    private(set) var isMenuOpen = false

    /// What the menu's controls change: the user's settings, Retry, the
    /// updates, and what only AppDelegate does.
    private let settings: UserSettings
    private let session: PlayerSession
    private let updates: any UpdateCommands
    private weak var actions: (any AppActions)?
    /// Detection's, Fades' and Advanced's settings, as Settings changes them.
    private let settingsModel: SettingsModel?
    /// What closes the menu (clicks elsewhere, another desktop) and what it
    /// follows while open (Option, for an added app's Remove).
    private var monitors: [Any] = []
    private var spaceObserver: NSObjectProtocol?
    /// Another window becoming key while the menu is open.
    private var keyWindowObserver: NSObjectProtocol?
    /// The content's height, as last measured.
    private var contentHeight: CGFloat = 0
    /// The panel follows the content's height at the end of this pass.
    private var followsContent = false

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
        model.hasSettings = settingsModel != nil
        model.settings = settingsModel
        model.perform = { [weak self] in self?.perform($0) }
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            // As a menu does: it opens as the button goes down.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        renderIcon()
        prepareContent()
    }

    /// Removes the item from the menu bar (tests clean up with it).
    func remove() {
        close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Rendering

    /// The icon follows at once, and the menu while it's open; a closed
    /// menu catches up when it next opens (`prepareContent`).
    private func render() {
        renderIcon()
        guard isMenuOpen else { return }
        model.status = status
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

    /// Gets the menu ready for `status` as it opens: the apps listed now,
    /// the players and Ignored Apps folded, the settings as left.
    private func prepareContent() {
        model.status = status
        model.listedSources = status.activeSources
        model.listedRecentSources = status.recentSources()
        model.isChoosingPlayer = false
        model.playerSearch = ""
        model.highlightedPlayerID = nil
        model.showsIgnoredApps = false
        model.isAntiDotMode = settings.state.detection != .audioLevels
        model.isOptionHeld = NSEvent.modifierFlags.contains(.option)
        model.announcesRetryOutcome = false
    }

    // MARK: - Opening and closing

    @objc private func statusItemClicked() {
        isMenuOpen ? close() : open()
    }

    /// Opens the menu under its menu bar item, the app first bringing the
    /// status up to date (`AppActions.menuWillOpen`). `showsPanel` off: the
    /// menu is ready and counts as open, but nothing shows (tests).
    func open(showsPanel: Bool = true) {
        guard !isMenuOpen else { return }
        actions?.menuWillOpen()
        prepareContent()
        isMenuOpen = true
        watchOtherWindows()
        guard showsPanel else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Its content as it opens, measured before it's placed.
        panel.contentView?.layoutSubtreeIfNeeded()
        placePanel(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        // As macOS's menus open: nothing focused, even with keyboard
        // navigation on, so Space doesn't toggle Auto-Pause straight away.
        panel.makeFirstResponder(nil)
        statusItem.button?.highlight(true)
        watchWhileOpen()
    }

    /// Closes the menu, at once.
    func close() {
        guard isMenuOpen else { return }
        isMenuOpen = false
        panel?.orderOut(nil)
        statusItem.button?.highlight(false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
        if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) }
        keyWindowObserver = nil
    }

    /// Closes the menu if it's open: an alert, such as an update check's
    /// result, can't show over it.
    func closeMenu() async {
        close()
    }

    private func makePanel() -> MenuPanel {
        let view = MenuPanelView(model: model, settings: settingsModel) { [weak self] in self?.contentHeightChanged($0) }
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = [] // under the hidden title bar too
        // A size to lay out in before the panel has its own: with none, its
        // content measures nothing.
        hosting.frame = NSRect(x: 0, y: 0, width: menuContentWidth, height: 600)
        let panel = MenuPanel(content: hosting)
        panel.onCancel = { [weak self] in self?.close() }
        panel.onKey = { [weak self] in self?.handleKey($0) ?? false }
        hosting.layoutSubtreeIfNeeded()
        contentHeight = max(contentHeight, hosting.fittingSize.height)
        return panel
    }

    /// Under the menu bar item, its left edge at the item's (kept on the
    /// screen), as tall as its content but never past the screen's bottom.
    private func placePanel(_ panel: MenuPanel) {
        guard let button = statusItem.button, let window = button.window,
              let screen = window.screen ?? NSScreen.main else { return }
        let item = window.convertToScreen(button.convert(button.bounds, to: nil))
        let frame = Self.panelFrame(under: item, in: screen.visibleFrame, width: menuContentWidth, contentHeight: contentHeight)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// The panel's frame under the menu bar item at `item`: its left edge at
    /// the item's, kept 6 pt inside the screen's `visible` part, 4 pt under
    /// it, as tall as its content but never past the screen's bottom.
    static func panelFrame(under item: NSRect, in visible: NSRect, width: CGFloat, contentHeight: CGFloat) -> NSRect {
        let x = min(max(item.minX, visible.minX + 6), visible.maxX - width - 6)
        let top = min(item.minY - 4, visible.maxY)
        let height = fittingHeight(contentHeight, top: top, in: visible)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }

    /// A height of `height` for a panel whose top edge is at `top`, but
    /// never past 6 pt above the screen's bottom (the rest scrolls).
    static func fittingHeight(_ height: CGFloat, top: CGFloat, in visible: NSRect) -> CGFloat {
        min(height, top - visible.minY - 6)
    }

    /// The content's height changed (a part folded or unfolded, the status
    /// line wrapped): the panel follows, animated while it shows, once its
    /// parts have all reported (a fold moves two of them in one pass).
    private func contentHeightChanged(_ height: CGFloat) {
        contentHeight = height
        guard isMenuOpen, panel?.isVisible == true, !followsContent else { return }
        followsContent = true
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated { self?.followContent() }
        }
    }

    private func followContent() {
        followsContent = false
        guard isMenuOpen, let panel, panel.isVisible, let screen = panel.screen else { return }
        panel.setContentHeight(Self.fittingHeight(contentHeight, top: panel.frame.maxY, in: screen.visibleFrame),
                               animated: !Self.reducesMotion)
    }

    /// Closes the menu on a click outside it (in another app, or another of
    /// AutoHush's windows); follows Option.
    private func watchWhileOpen() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.flagsChanged), handler: { [weak self] event in
            let isFlags = event.type == .flagsChanged
            let optionHeld = event.modifierFlags.contains(.option)
            let windowNumber = event.windowNumber
            MainActor.assumeIsolated {
                guard let self else { return }
                if isFlags {
                    self.model.isOptionHeld = optionHeld
                } else if windowNumber != self.panel?.windowNumber, windowNumber != self.statusItem.button?.window?.windowNumber {
                    self.close()
                }
            }
            return event
        }) { monitors.append(local) }
    }

    /// Closes the menu as another window becomes key (one of AutoHush's, or
    /// an alert, that a choice in the menu brought forward), or on another
    /// desktop.
    private func watchOtherWindows() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.close() } }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            // Its identity, which can cross into the main actor (the window can't).
            let window = (note.object as? NSWindow).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let window, window != self.panel.map(ObjectIdentifier.init) else { return }
                self.close()
            }
        }
    }

    /// ↑ ↓ move among the unfolded players and Return chooses, as in a
    /// menu (the search takes them itself while it has the keyboard).
    func handleKey(_ event: NSEvent) -> Bool {
        guard model.isChoosingPlayer else { return false }
        switch event.keyCode {
        case 126: perform(.moveHighlight(-1))
        case 125: perform(.moveHighlight(1))
        case 36, 76: perform(.chooseHighlighted)
        default: return false
        }
        return true
    }

    private static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Folds or unfolds a part of the menu, smoothly unless Reduce Motion is on.
    private func animated(_ change: () -> Void) {
        withAnimation(Self.reducesMotion ? nil : MenuPanelView.animation, change)
    }

    // MARK: - Actions

    /// What the menu's controls ask for. Switches, folding and the players'
    /// search act at once and keep the menu open; what opens a window or
    /// opens a window closes it first, as a menu's rows do; choosing a player
    /// keeps it open (the user, 2026-10-18).
    func perform(_ command: StatusMenuCommand) {
        switch command {
        case .toggleAutoPause:
            settings.toggleAutoPause()
        case .setIgnored(let source, let ignored):
            settings.setIgnored(source, ignored)
        case .togglePlayerList:
            animated {
                model.isChoosingPlayer.toggle()
                model.playerSearch = ""
                model.highlightedPlayerID = nil
            }
        case .choosePlayer(let id):
            // In place (the user, 2026-10-18): the list folds, and the card,
            // its checks and the settings follow the new player. A window the
            // choice opens (Add a Web App, learning) or an alert closes the
            // menu as it comes forward (`watchOtherWindows`).
            animated {
                model.isChoosingPlayer = false
                model.playerSearch = ""
                model.highlightedPlayerID = nil
            }
            actions?.choosePlayer(id)
        case .searchPlayers(let search):
            guard model.isChoosingPlayer else { return } // a closing field handing its text back
            model.playerSearch = search
            if let highlighted = model.highlightedPlayerID, !model.players.choosable.contains(where: { $0.id == highlighted }) {
                model.highlightedPlayerID = nil
            }
        case .moveHighlight(let step):
            model.highlightedPlayerID = model.players.highlight(from: model.highlightedPlayerID, by: step)
        case .chooseHighlighted:
            guard let id = model.highlightedPlayerID ?? model.players.choosable.first?.id else { return }
            perform(.choosePlayer(id))
        case .toggleSettings(let part):
            animated {
                if model.unfoldedSettings.contains(part) { model.unfoldedSettings.remove(part) } else { model.unfoldedSettings.insert(part) }
            }
        case .toggleIgnoredApps:
            animated { model.showsIgnoredApps.toggle() }
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
        case .snooze, .removeAddedApp, .addApp, .addWebApp, .resolveWarning, .reopenAutoHush, .useAntiDotMode,
             .showUpdate, .openSettings, .showDiagnostics, .updates, .showAbout, .showControlError, .learnControls,
             .reopenPlayer, .unmutePlayer, .quit:
            close()
            // Once the menu has closed, as for a menu's rows.
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                MainActor.assumeIsolated { self?.run(command) }
            }
        }
    }

    private func run(_ command: StatusMenuCommand) {
        switch command {
        case .snooze(let snooze):        settings.snooze(snooze)
        case .removeAddedApp(let id):    actions?.removeAddedApp(id)
        case .addApp:                    actions?.openAddApp()
        case .addWebApp:                 actions?.openAddWebApp()
        case .resolveWarning(let need):  actions?.requestPermission(need)
        case .reopenAutoHush:            actions?.reopenAutoHush()
        case .useAntiDotMode:            settings.setDetectionMethod(.playbackSignals)
        case .showUpdate:                updates.presentAvailableUpdate()
        case .openSettings:              actions?.openSettings(page: nil)
        case .showDiagnostics:           actions?.openSettings(page: .diagnostics)
        case .updates:                   updates.presentAvailableUpdate() // checking keeps the menu open: `perform`
        case .showAbout:                 actions?.openSettings(page: .about)
        case .showControlError:          actions?.showControlError()
        case .learnControls:             actions?.learnControlsAgain()
        case .reopenPlayer:              actions?.reopenPlayer()
        case .unmutePlayer:              actions?.unmutePlayer()
        case .quit:                      actions?.quit()
        case .toggleAutoPause, .setIgnored, .togglePlayerList, .choosePlayer, .searchPlayers, .moveHighlight, .chooseHighlighted,
             .toggleSettings, .toggleIgnoredApps, .retry:
            break // they act in perform(_:)
        }
    }
}
