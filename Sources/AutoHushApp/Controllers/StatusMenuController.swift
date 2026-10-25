import AppKit
import SwiftUI
import AutoHushKit

/// Owns the menu bar item and the menu it opens, and renders an `AppStatus`
/// into them. The menu is AutoHush's own panel (`MenuPanel`), so its parts
/// fold and unfold smoothly; its layout, part by part, is STYLE_GUIDE.md's
/// (Layout → Menu, and its components), and README's "Using AutoHush" says
/// what each part does.
///
/// The menu follows `status` while it's open, but the apps listed under
/// Playing Now and Recently Played are fixed then, so no row moves under the
/// pointer. Only what's between the card and the buttons scrolls, the last
/// rows fading while more is below. It closes on a click outside it, on
/// Escape, when the desktop changes, as another window becomes key, and
/// before anything opens a window. It has no keyboard shortcuts: AutoHush
/// has none of its own. The side windows are in `+SideWindow`, the keys in
/// `+Keys`.
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
    var sidePanel: MenuPanel?
    /// The side window's content height, as last measured.
    var sideHeight: CGFloat = 0
    /// When a click elsewhere last closed the menu: a click on the menu bar
    /// item itself closes it that way first, as its mouse goes down.
    private var lastClosedByClick: Date?
    /// The row that opens a side window the pointer rests on, if any.
    var hoveredSideRow: MenuSidePart?
    /// The menu's part the pointer last came onto.
    var pointerSection: MenuSection?
    /// How long the pointer rests on a row before its side window opens,
    /// and stays on another part before it closes (so the way to the side
    /// window may cross the menu), as macOS's submenus wait.
    static let sideOpenDelay: TimeInterval = 0.15
    static let sideCloseDelay: TimeInterval = 0.3
    private(set) var isMenuOpen = false

    /// Each settings part's fold under way, while its other settings fade
    /// out: another click on its title undoes it.
    private(set) var foldTasks: [MenuSettingsPart: Task<Void, Never>] = [:]
    /// The side window opening once the pointer rests on its row, and
    /// closing once it stays on another part: each new move replaces it.
    var sideOpenTask: Task<Void, Never>?
    var sideCloseTask: Task<Void, Never>?

    /// Where it hears that another window became key, and that the desktop
    /// changed (tests give it their own, so no other test's window counts).
    var notificationCenter = NotificationCenter.default
    var workspaceCenter = NSWorkspace.shared.notificationCenter
    /// Reduce Motion, read at each change (tests set it).
    var reducesMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// The waits of the fold's fade and the side windows' timing (tests
    /// shorten them).
    var pause: @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    /// Where the pointer is, in the screen's coordinates (tests move it).
    var pointerLocation: @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    /// The clock a click on the menu bar item is timed by (tests move it).
    var now: @MainActor () -> Date = Date.init
    /// The menu bar item's frame, from its window unless set (tests, whose
    /// item the menu bar may not have placed).
    var itemFrame: (@MainActor () -> CGRect?)?
    /// The menu's and the side window's frames, from their windows unless
    /// set (tests, which show no window).
    var windowFrames: (@MainActor () -> (menu: CGRect, side: CGRect)?)?

    /// What the menu's controls change: the user's settings, Try Again, the
    /// updates, and what only AppDelegate does.
    private let settings: UserSettings
    private let session: PlayerSession
    private let updates: any UpdateCommands
    private(set) weak var actions: any AppActions?
    /// Detection's, Fades' and Advanced's settings, as Settings changes them.
    private let settingsModel: SettingsModel?
    /// What closes the menu (clicks elsewhere, another desktop) and what it
    /// follows while open (Option, for an added app's Remove).
    private var monitors: [Any] = []
    private var spaceObserver: any NSObjectProtocol?
    /// Another window becoming key while the menu is open.
    private var keyWindowObserver: any NSObjectProtocol?
    /// The content's height, as last measured.
    private var contentHeight: CGFloat = 0
    /// The panel follows the content's height at the end of this pass.
    private var followsContent = false

    init(status: AppStatus = AppStatus(), settings: UserSettings, session: PlayerSession,
         updates: any UpdateCommands, actions: any AppActions?, settingsModel: SettingsModel? = nil) {
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
    /// the side windows closed, the settings as left.
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
        model.isAntiDotMode = settings.state.detection.isAntiDot
        model.isOptionHeld = NSEvent.modifierFlags.contains(.option)
        model.announcesRetryOutcome = false
        model.announcesResumeOutcome = false
    }

    // MARK: - Opening and closing

    /// A click on the menu bar item opens the menu, and closes it while
    /// it's open, as macOS's own menu bar items do (the user, 2026-10-18).
    /// The click that closed it from outside, over the item (`watchWhileOpen`),
    /// mustn't open it again at once.
    @objc func statusItemClicked() {
        if isMenuOpen {
            close()
        } else if let closed = lastClosedByClick, now().timeIntervalSince(closed) < 0.4 {
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
        sideOpenTask?.cancel()
        sideCloseTask?.cancel()
        sidePanel?.orderOut(nil)
        panel?.orderOut(nil)
        statusItem.button?.highlight(false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let spaceObserver { workspaceCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
        if let keyWindowObserver { notificationCenter.removeObserver(keyWindowObserver) }
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
        model.isCappedByScreen = Self.isCapped(height: frame.height, content: contentHeight)
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

    /// Whether a window `height` tall shows less than its `content`: the
    /// screen caps it, and only then does it show that more is below.
    static func isCapped(height: CGFloat, content: CGFloat) -> Bool {
        height < content.rounded() - 0.5
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
        let height = Self.fittingHeight(contentHeight, top: panel.frame.maxY, in: screen.visibleFrame)
        model.isCappedByScreen = Self.isCapped(height: height, content: contentHeight)
        panel.setContentHeight(height, animated: !reducesMotion())
    }

    /// Closes the menu on a click outside it (in another app, or another of
    /// AutoHush's windows); follows Option.
    private func watchWhileOpen() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeForClickElsewhere() }
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

    /// A click outside the menu closes it. One on the menu bar item itself
    /// reaches the item too, as its next click: noted, so it doesn't open
    /// the menu again (`statusItemClicked`). Only that one (the full check,
    /// 2026-10-18: a quick click elsewhere and then on the icon opened nothing).
    func closeForClickElsewhere() {
        close()
        if let item = itemFrame?() ?? statusItem.button?.window?.frame, item.contains(pointerLocation()) {
            lastClosedByClick = now()
        }
    }

    /// Closes the menu as another window becomes key (one of AutoHush's, or
    /// an alert, that a choice in the menu brought forward), or on another
    /// desktop.
    private func watchOtherWindows() {
        spaceObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.close() } }
        keyWindowObserver = notificationCenter.addObserver(
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

    /// Folds or unfolds a part of the menu, smoothly unless Reduce Motion is on.
    func animated(_ change: () -> Void) {
        withAnimation(reducesMotion() ? nil : MenuPanelView.animation, change)
    }

    /// How long a part's other settings take to fade out before it folds.
    static let foldFade: TimeInterval = 0.15

    /// Folds `part`: its other settings fade out first, then go as the rows
    /// under them move up, so none overlap (the user, 2026-10-18). At once
    /// with Reduce Motion.
    private func fold(_ part: MenuSettingsPart) {
        foldTasks[part]?.cancel()
        guard !reducesMotion() else {
            model.unfoldedSettings.remove(part)
            return
        }
        withAnimation(.easeOut(duration: Self.foldFade)) { _ = model.foldingSettings.insert(part) }
        let pause = pause
        foldTasks[part] = Task { [weak self] in
            await pause(Self.foldFade)
            // Unfolded again meanwhile: another click cancelled it.
            guard !Task.isCancelled, let self, self.model.foldingSettings.contains(part) else { return }
            self.animated {
                self.model.foldingSettings.remove(part)
                self.model.unfoldedSettings.remove(part)
            }
            self.foldTasks[part] = nil
        }
    }

    // MARK: - Actions

    /// What the menu's controls ask for. Switches, folding and the players'
    /// search act at once and keep the menu open; what opens a window or an
    /// alert closes it first, as a menu's rows do; choosing a player keeps
    /// it open (the user, 2026-10-18).
    func perform(_ command: StatusMenuCommand) {
        switch command {
        case .toggleAutoPause:
            settings.toggleAutoPause()
        case .setIgnored(let source, let ignored):
            settings.setIgnored(source, ignored)
        case .choosePlayer(let id):
            // In place (the user, 2026-10-18): the side window closes, and the
            // card, its checks and the settings follow the new player. A window
            // the choice opens (Add a Web App, learning) or an alert closes the
            // menu as it comes forward (`watchOtherWindows`).
            closeSide()
            actions?.choosePlayer(id)
        case .searchPlayers(let search):
            guard model.isChoosingPlayer else { return } // a closing field handing its text back
            model.playerSearch = search
        case .typeInSearch:
            searchTakesKeyboard()
        case .moveHighlight(let step):
            model.sideKeyboard.move(step)
        case .chooseHighlighted:
            // The first player the search left, only while something is typed
            // (the full check, 2026-10-18: with none, Return changed the player).
            guard !model.sideKeyboard.press(), !model.playerSearch.isEmpty,
                  let id = model.players.choosable.first?.id else { return }
            perform(.choosePlayer(id))
        case .toggleSettings(let part):
            if model.foldingSettings.contains(part) {
                // Clicked again while its settings fade out: they stay.
                foldTasks[part]?.cancel()
                foldTasks[part] = nil
                withAnimation(.easeOut(duration: Self.foldFade)) { _ = model.foldingSettings.remove(part) }
            } else if model.unfoldedSettings.contains(part) {
                fold(part)
            } else {
                animated { _ = model.unfoldedSettings.insert(part) }
            }
        case .openSide(let part):
            guard model.openSide != part else { return }
            open(part)
        case .hoverSideRow(let part, let inside):
            hoverSideRow(part, inside)
        case .pointerEntered(let section):
            pointerEntered(section)
        case .retry:
            model.announcesRetryOutcome = true
            session.retry() // the card shows how it goes
        case .retryResume:
            model.announcesResumeOutcome = true
            session.retryResume() // the card shows how it goes
        case .updates where status.updateOffer == nil:
            // The menu stays open, its button saying "Checking…", until the
            // result: its alert closes the menu first (`closeMenu`).
            guard !model.isCheckingForUpdates else { return }
            model.isCheckingForUpdates = true
            Task { [weak self] in
                await self?.updates.checkNow()
                self?.model.isCheckingForUpdates = false
            }
        default:
            guard command.closesMenuFirst else { return }
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
        case .ignoreAnotherApp:          IgnoreAppsPicker.run(player: status.chosenPlayer) { settings.setIgnored($0, true) }
        case .resolveWarning(let need):  actions?.requestPermission(need)
        case .reopenAutoHush:            actions?.reopenAutoHush()
        // Through Settings' model, whose guard keeps AntiDot mode off for a
        // player only its sound tells about (U18, the full check, 2026-10-19).
        case .useAntiDotMode:            settingsModel?.useAntiDotMode()
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
        default:                         break // they act in perform(_:) (`closesMenuFirst`)
        }
    }
}
