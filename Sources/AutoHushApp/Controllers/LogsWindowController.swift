import AppKit
import SwiftUI

/// AutoHush's logs, from Settings → Diagnostics' Show Logs…: a window the
/// user resizes (never full screen), which opens where and as big as it
/// was left, the first time centered. It follows new lines while it's open.
@MainActor
final class LogsWindowController: PlacedWindowController, NSWindowDelegate {
    static let minimumSize = NSSize(width: 760, height: 440)
    static let initialSize = NSSize(width: 960, height: 640)
    /// Where macOS keeps the window's place and size between launches (a
    /// new name with the bigger size, so the old, smaller one isn't kept).
    static let frameName = "Logs Window"

    let model: LogsModel

    /// `frameName`: where the window's place and size are kept; tests give
    /// each window a name of its own, as Settings' do.
    init(model: LogsModel, frameName: String = LogsWindowController.frameName) {
        self.model = model
        let hosting = NSHostingController(rootView: LogsView(model: model))
        hosting.sizingOptions = []
        // As AutoHush's other windows: the title bar part of the window, its title in bold.
        super.init(content: hosting, frameName: frameName, minimumSize: Self.minimumSize, initialSize: Self.initialSize,
                   toolbar: NSToolbar(identifier: "AutoHushLogs"))
        window?.title = Self.title
        window?.delegate = self
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
        placeOnce()
        window?.showInFront()
    }

    func windowWillClose(_ notification: Notification) {
        model.close()
    }
}
