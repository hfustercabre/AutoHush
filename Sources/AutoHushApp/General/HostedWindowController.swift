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
        guard let window else { return }
        if !window.isVisible {
            // Sized to its content first: centered at its first, empty size,
            // it would grow from the middle of the screen, partly off it.
            if let fitting = window.contentView?.fittingSize, fitting.width > 0, fitting.height > 0 {
                window.setContentSize(fitting)
            }
            window.center()
        }
        window.showInFront()
    }

    /// Brings it in front of other apps' windows, on the desktop the user is
    /// on, without making it key: for while AutoHush's menu opens.
    func bringForward() {
        guard isVisible else { return }
        window?.bringForward()
    }
}
