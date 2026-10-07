import AppKit
import SwiftUI

/// A window around SwiftUI content, sized to it: titled and closable, and
/// kept when closed, so it shows again at once. It's shown in front, and
/// centered when it comes on screen. The welcome, learning and "Add a Web
/// App" windows are these.
@MainActor
class HostedWindowController: NSWindowController {
    init(content: NSViewController, title: String) {
        let window = NSWindow(contentViewController: content)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A hosting controller for `view` that sizes the window to it.
    static func sizedToFit<Content: View>(_ view: Content) -> NSHostingController<Content> {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        return hosting
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        if !isVisible { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }
}
