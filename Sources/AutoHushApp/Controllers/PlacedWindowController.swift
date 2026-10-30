import AppKit

/// A window the user resizes, never full screen, which opens where and as
/// big as it was left, the first time centered (`placeOnce`), with
/// AutoHush's title bar: Settings and the logs window. Kept when closed.
@MainActor
class PlacedWindowController: NSWindowController {
    /// The window has a place: kept from a previous launch, or centered once.
    private var isPlaced: Bool

    /// A window around `content`, resized within `minimumSize` and
    /// `maximumSize`, at `initialSize` until it has a place and size of its
    /// own, kept under `frameName` (tests give each window a name of its
    /// own, since AppKit gives a name to one window at a time). `toolbar`
    /// and `transparentTitleBar`: see `useAutoHushTitleBar`.
    init(content: NSViewController, frameName: String, minimumSize: NSSize, maximumSize: NSSize? = nil,
         initialSize: NSSize, toolbar: NSToolbar, transparentTitleBar: Bool = true) {
        let window = NSWindow(contentViewController: content)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // Resizable, but never full screen, as no AutoHush window: the green
        // button zooms it within its largest size.
        window.collectionBehavior.insert(.fullScreenNone)
        window.isReleasedWhenClosed = false
        window.useAutoHushTitleBar(toolbar, transparent: transparentTitleBar)
        window.contentMinSize = minimumSize
        if let maximumSize { window.contentMaxSize = maximumSize }
        window.setContentSize(initialSize)
        isPlaced = window.setFrameUsingName(frameName)
        super.init(window: window)
        // On the controller, once it has the window: a controller gives the
        // window it gets its own name, on macOS 14 and 15 an empty one too,
        // which cleared the window's (it opened at its first place and size
        // at each launch).
        windowFrameAutosaveName = frameName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Centered as it first shows, when no place was kept for it.
    func placeOnce() {
        guard !isPlaced else { return }
        window?.center()
        isPlaced = true
    }
}
