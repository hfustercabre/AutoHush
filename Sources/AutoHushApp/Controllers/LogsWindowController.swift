import AppKit
import SwiftUI

/// AutoHush's logs, from Settings → Diagnostics' Show Logs…: a window the
/// user resizes (never full screen), which opens where and as big as it
/// was left, the first time centered. It follows new lines while it's open.
@MainActor
final class LogsWindowController: NSWindowController, NSWindowDelegate {
    static let minimumSize = NSSize(width: 760, height: 440)
    static let initialSize = NSSize(width: 960, height: 640)
    /// Where macOS keeps the window's place and size between launches (a
    /// new name with the bigger size, so the old, smaller one isn't kept).
    static let frameName = "Logs Window"

    let model: LogsModel
    /// The window has a place: kept from a previous launch, or centered once.
    private var isPlaced: Bool

    init(model: LogsModel) {
        self.model = model
        let hosting = NSHostingController(rootView: LogsView(model: model))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.collectionBehavior.insert(.fullScreenNone)
        // As AutoHush's other windows: the title bar part of the window, its title in bold.
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        let toolbar = NSToolbar(identifier: "AutoHushLogs")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumSize
        window.setContentSize(Self.initialSize)
        isPlaced = window.setFrameUsingName(Self.frameName)
        window.setFrameAutosaveName(Self.frameName)
        window.title = Self.title
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static var title: String {
        String(localized: "AutoHush Logs",
               comment: "Title of the window that shows what AutoHush logged (opened from Settings → Diagnostics), and the name of the file its Save… writes")
    }

    func show() {
        // Shown again while open (or minimized): the search stays.
        if window?.isOpen != true { model.open() }
        if !isPlaced {
            window?.center()
            isPlaced = true
        }
        window?.showInFront()
    }

    func windowWillClose(_ notification: Notification) {
        model.close()
    }
}
