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
/// has none of its own. Opening and closing it are in `+Opening`, what its
/// controls do in `+Commands`, the side windows in `+SideWindow`, the keys
/// in `+Keys`.
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
    var panel: MenuPanel?
    /// The side window beside it (the players, or the ignored apps), made
    /// the first time one opens.
    var sidePanel: MenuPanel?
    /// The side window's content height, as last measured.
    var sideHeight: CGFloat = 0
    /// When a click elsewhere last closed the menu: a click on the menu bar
    /// item itself closes it that way first, as its mouse goes down.
    var lastClosedByClick: Date?
    /// The row that opens a side window the pointer rests on, if any.
    var hoveredSideRow: MenuSidePart?
    /// The menu's part the pointer last came onto.
    var pointerSection: MenuSection?
    /// How long the pointer rests on a row before its side window opens,
    /// and stays on another part before it closes (so the way to the side
    /// window may cross the menu), as macOS's submenus wait.
    static let sideOpenDelay: TimeInterval = 0.15
    static let sideCloseDelay: TimeInterval = 0.3
    var isMenuOpen = false

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
    let settings: UserSettings
    let session: PlayerSession
    let updates: any UpdateCommands
    private(set) weak var actions: any AppActions?
    /// The settings the menu reads (AntiDot mode, the card's checks), as
    /// Settings changes them.
    let settingsModel: SettingsModel?
    /// What closes the menu (clicks elsewhere, another desktop) and what it
    /// follows while open (Option, for an added app's Remove).
    var monitors: [Any] = []
    var spaceObserver: any NSObjectProtocol?
    /// Another window becoming key while the menu is open.
    var keyWindowObserver: any NSObjectProtocol?
    /// The menu bar item's window moving (`followItemMoves`).
    private var itemMoveObserver: any NSObjectProtocol?
    /// The content's height, as last measured.
    var contentHeight: CGFloat = 0
    /// The panel follows the content's height at the end of this pass.
    var followsContent = false

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
        if let itemMoveObserver { notificationCenter.removeObserver(itemMoveObserver) }
        itemMoveObserver = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Settings → General's hidden-icon note is read again each time macOS
    /// moves the item's window: as it places a new item, whose window has
    /// no place for a moment (U8, 2026-10-27: `{0, 0}` with no height, read
    /// as shown whatever came next), on a ⌘-drag, and as other apps' icons
    /// come and go.
    func followItemMoves() {
        guard itemMoveObserver == nil, let window = statusItem.button?.window else { return }
        itemMoveObserver = notificationCenter.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.settingsModel?.refreshMenuBarIcon() } }
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
    func prepareContent() {
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
}
