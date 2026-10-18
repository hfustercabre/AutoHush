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
///  Media Player
///  [icon] Spotify · Supported app             ›   opens the players beside the menu
///                                                 (a side window: search, Supported
///                                                 Apps, Other Apps, Safari Web Apps)
///  ⚠ Allow Audio Recording Access…        (only when something needs fixing)
///  Turn off for  [5 min] [15 min] [30 min] [1 hr] [24 hr]
///  ─────  Playing Now · Recently Played  (each app with its switch)
///  ─────  Ignored Apps: [icons] VLC, Messages ›  (a side window: each with its switch)
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
    /// The side window beside it (the players, or the ignored apps), made
    /// the first time one opens.
    private(set) var sidePanel: MenuPanel?
    /// The side window's content height, as last measured.
    private var sideHeight: CGFloat = 0
    /// When a click elsewhere last closed the menu: a click on the menu bar
    /// item itself closes it that way first, as its mouse goes down.
    private var lastClosedByClick: Date?
    /// The row that opens a side window the pointer rests on, if any.
    private var hoveredSideRow: MenuSidePart?
    /// The menu's part the pointer last came onto.
    private var pointerSection: MenuSection?
    /// How long the pointer rests on a row before its side window opens,
    /// and stays on another part before it closes (so the way to the side
    /// window may cross the menu), as macOS's submenus wait.
    static let sideOpenDelay: TimeInterval = 0.15
    static let sideCloseDelay: TimeInterval = 0.3
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
        model.showsIgnoredApps = false
        model.listedIgnoredApps = status.ignoredApps
        // As macOS's menus open: nothing highlighted.
        model.keyboard.clear()
        model.sideKeyboard.clear()
        hoveredSideRow = nil
        pointerSection = nil
        model.isAntiDotMode = settings.state.detection != .audioLevels
        model.isOptionHeld = NSEvent.modifierFlags.contains(.option)
        model.announcesRetryOutcome = false
    }

    // MARK: - Opening and closing

    /// A click on the menu bar item opens the menu, and closes it while
    /// it's open, as macOS's own menu bar items do (the user, 2026-10-18).
    /// The click that closed it from outside (`watchWhileOpen`) mustn't
    /// open it again at once.
    @objc private func statusItemClicked() {
        if isMenuOpen {
            close()
        } else if let closed = lastClosedByClick, Date().timeIntervalSince(closed) < 0.4 {
            lastClosedByClick = nil
        } else {
            open()
        }
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
        sidePanel?.orderOut(nil)
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
        // Escape closes the side window first, as a submenu, then the menu.
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if model.openSide != nil { closeSide() } else { close() }
        }
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

    // MARK: - The side window

    /// Opens the side window the model asks for beside the menu, level with
    /// its row, or closes it (W2, the user's pick, 2026-10-18). Escape closes
    /// it first, then the menu.
    private func showSide() {
        guard isMenuOpen, let panel, panel.isVisible, model.openSide != nil else {
            if sidePanel?.isVisible == true {
                sidePanel?.orderOut(nil)
                if isMenuOpen { panel?.makeKey() }
            }
            return
        }
        let side = sidePanel ?? makeSidePanel()
        sidePanel = side
        side.contentView?.layoutSubtreeIfNeeded()
        placeSide(side, beside: panel)
        side.orderFrontRegardless()
        // The menu keeps the keyboard, so its switches stay drawn active
        // (AppKit draws a window that isn't key as inactive): typing goes to
        // the players' search, ↑ ↓ Return to their list (`handleKey`). Only
        // VoiceOver moves into the side window, to read it.
        side.takesKey = NSWorkspace.shared.isVoiceOverEnabled
        if side.takesKey { side.makeKey() } else { panel.makeKey() }
    }

    /// Opens `part`'s side window, closing the other.
    private func open(_ part: MenuSidePart) {
        model.isChoosingPlayer = part == .players
        model.showsIgnoredApps = part == .ignoredApps
        model.playerSearch = ""
        model.sideKeyboard.clear()
        // Listed as they are now, fixed while it's open.
        if part == .ignoredApps { model.listedIgnoredApps = status.ignoredApps }
        showSide()
    }

    /// The pointer is over the side window.
    private var pointerIsInSide: Bool {
        guard let side = sidePanel, side.isVisible else { return false }
        return side.frame.contains(NSEvent.mouseLocation)
    }

    /// Closes the side window, the menu staying open.
    private func closeSide() {
        model.isChoosingPlayer = false
        model.showsIgnoredApps = false
        model.playerSearch = ""
        model.sideKeyboard.clear()
        showSide()
    }

    private func makeSidePanel() -> MenuPanel {
        let view = MenuSidePanelView(model: model) { [weak self] in self?.sideHeightChanged($0) }
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(x: 0, y: 0, width: MenuSidePanelView.width, height: 600)
        let side = MenuPanel(content: hosting)
        side.title = "AutoHush"
        side.onCancel = { [weak self] in self?.closeSide() }
        side.onKey = { [weak self] in self?.handleKey($0) ?? false }
        return side
    }

    private func placeSide(_ side: MenuPanel, beside panel: MenuPanel) {
        guard let part = model.openSide, let screen = panel.screen ?? NSScreen.main else { return }
        let rowTop = panel.frame.maxY - (model.sideRowTops[part] ?? 0)
        side.setFrame(Self.sideFrame(rowTop: rowTop, menu: panel.frame, in: screen.visibleFrame,
                                     width: MenuSidePanelView.width, contentHeight: sideHeight),
                      display: true)
        side.invalidateShadow()
    }

    /// The side window's frame: beside the menu, on its left (the menu sits
    /// near the screen's right edge) unless there's no room there, then on
    /// its right; its top level with the row that opened it (`rowTop`, the
    /// first row inside level with that row), as tall as its content but
    /// on the screen, moved up if it would go past the screen's bottom.
    static func sideFrame(rowTop: CGFloat, menu: NSRect, in visible: NSRect, width: CGFloat, contentHeight: CGFloat) -> NSRect {
        let gap: CGFloat = 6
        let x = menu.minX - gap - width >= visible.minX + 6 ? menu.minX - gap - width : menu.maxX + gap
        let height = min(contentHeight, visible.height - 12)
        let top = max(min(rowTop + 8, visible.maxY - 6), visible.minY + 6 + height)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }

    /// Its content's height changed (another side, a search): the window
    /// follows at the end of this pass, as the menu does (resized during
    /// SwiftUI's layout, its content kept a stale frame, 2026-10-18).
    private func sideHeightChanged(_ height: CGFloat) {
        sideHeight = height
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isMenuOpen, let panel = self.panel, let side = self.sidePanel, side.isVisible else { return }
                self.placeSide(side, beside: panel)
            }
        }
    }

    /// Closes the menu on a click outside it (in another app, or another of
    /// AutoHush's windows); follows Option.
    private func watchWhileOpen() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.close()
                self.lastClosedByClick = Date()
            }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.flagsChanged), handler: { [weak self] event in
            let isFlags = event.type == .flagsChanged
            let optionHeld = event.modifierFlags.contains(.option)
            let windowNumber = event.windowNumber
            MainActor.assumeIsolated {
                guard let self else { return }
                if isFlags {
                    self.model.isOptionHeld = optionHeld
                } else if windowNumber != self.panel?.windowNumber, windowNumber != self.sidePanel?.windowNumber,
                          windowNumber != self.statusItem.button?.window?.windowNumber {
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
                guard let self, let window, window != self.panel.map(ObjectIdentifier.init),
                      window != self.sidePanel.map(ObjectIdentifier.init),
                      let key = NSApp.windows.first(where: { ObjectIdentifier($0) == window }),
                      Self.closesMenu(becomingKey: key, statusItemWindow: self.statusItem.button?.window) else { return }
                self.close()
            }
        }
    }

    /// Whether `window` becoming key is another window coming forward: a
    /// visible one, not the menu bar item's own (VoiceOver's press on a row
    /// makes that one key, 2026-10-18).
    static func closesMenu(becomingKey window: NSWindow, statusItemWindow: NSWindow?) -> Bool {
        window.isVisible && window !== statusItemWindow && window.level != .statusBar
    }

    /// The keys, as in macOS's menus, whatever the keyboard navigation
    /// setting (the user, 2026-10-18: "Arrows, as menus"): ↑ ↓ move the
    /// highlight through the menu's controls (`KeyHighlight`), or the side
    /// window's rows while it's open (the players' too: "Implement the same
    /// in the Media Player submenu"); Return or Space presses the one it's
    /// on; → opens a side window from its row, ← closes it; on a slider or a
    /// choice, ← and → change it. Among the players, typing goes to their
    /// search, and Return with nothing highlighted chooses the first one it
    /// left (the search takes the keys itself while it has the keyboard).
    /// Tab leaves the highlight to the keyboard's focus.
    func handleKey(_ event: NSEvent) -> Bool {
        if model.isChoosingPlayer, model.players.showsSearch, let typed = Self.typedText(event) {
            // Typed into the players' search while the menu keeps the keyboard.
            perform(.searchPlayers(typed.isEmpty ? String(model.playerSearch.dropLast()) : model.playerSearch + typed))
            return true
        }
        let inSide = model.openSide != nil
        let keyboard = inSide ? model.sideKeyboard : model.keyboard
        switch event.keyCode {
        case 48: // Tab: the keyboard's focus takes over
            model.keyboard.clear()
            model.sideKeyboard.clear()
            return false
        case 125, 126:
            // One highlight at a time: the keyboard's focus, if Tab gave it, goes.
            panel?.makeFirstResponder(nil)
            keyboard.move(event.keyCode == 125 ? 1 : -1)
            return true
        case 36, 76:
            if model.isChoosingPlayer {
                perform(.chooseHighlighted)
                return true
            }
            return keyboard.press()
        case 49:
            return keyboard.press()
        case 124:
            if !inSide, keyboard.highlightedOpensSide { return keyboard.press() }
            return keyboard.adjust(1)
        case 123:
            if inSide {
                closeSide()
                return true
            }
            return keyboard.adjust(-1)
        default:
            return false
        }
    }

    /// What a key press types into a search: its characters, "" for Delete
    /// (one character back), `nil` for a key that doesn't type (arrows,
    /// Return, Escape, a shortcut with Command or Control).
    static func typedText(_ event: NSEvent) -> String? {
        guard event.modifierFlags.isDisjoint(with: [.command, .control]) else { return nil }
        if event.keyCode == 51 { return "" } // Delete
        guard let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 })
        else { return nil }
        return characters
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
            model.isChoosingPlayer.toggle()
            model.showsIgnoredApps = false
            model.playerSearch = ""
            model.sideKeyboard.clear()
            showSide()
        case .choosePlayer(let id):
            // In place (the user, 2026-10-18): the side window closes, and the
            // card, its checks and the settings follow the new player. A window
            // the choice opens (Add a Web App, learning) or an alert closes the
            // menu as it comes forward (`watchOtherWindows`).
            model.isChoosingPlayer = false
            model.playerSearch = ""
            model.sideKeyboard.clear()
            showSide()
            actions?.choosePlayer(id)
        case .searchPlayers(let search):
            guard model.isChoosingPlayer else { return } // a closing field handing its text back
            model.playerSearch = search
        case .moveHighlight(let step):
            model.sideKeyboard.move(step)
        case .chooseHighlighted:
            guard !model.sideKeyboard.press(), let id = model.players.choosable.first?.id else { return }
            perform(.choosePlayer(id))
        case .toggleSettings(let part):
            animated {
                if model.unfoldedSettings.contains(part) { model.unfoldedSettings.remove(part) } else { model.unfoldedSettings.insert(part) }
            }
        case .toggleIgnoredApps:
            model.showsIgnoredApps.toggle()
            model.isChoosingPlayer = false
            // Listed as they are now, fixed while it's open.
            if model.showsIgnoredApps { model.listedIgnoredApps = status.ignoredApps }
            showSide()
        case .openSide(let part):
            guard model.openSide != part else { return }
            open(part)
        case .hoverSideRow(let part, let inside):
            if inside {
                hoveredSideRow = part
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.sideOpenDelay))
                    guard let self, self.isMenuOpen, self.hoveredSideRow == part, self.model.openSide != part else { return }
                    self.open(part)
                }
            } else if hoveredSideRow == part {
                hoveredSideRow = nil
            }
        case .pointerEntered(let section):
            pointerSection = section
            guard let open = model.openSide, section != open.section else { return }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.sideCloseDelay))
                guard let self, self.isMenuOpen, self.model.openSide == open,
                      self.pointerSection != open.section, !self.pointerIsInSide else { return }
                self.closeSide()
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
             .toggleSettings, .toggleIgnoredApps, .openSide, .hoverSideRow, .pointerEntered, .retry:
            break // they act in perform(_:)
        }
    }
}
