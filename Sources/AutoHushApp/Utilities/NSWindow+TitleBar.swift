import AppKit

extension NSWindow {
    /// AutoHush's title bar, as in Settings: part of the window, without its
    /// band or line, over the window's own background, and `toolbar` (an
    /// empty one, in a window without a toolbar of its own) shows the title
    /// in bold. `transparent` off leaves the title bar's look to macOS
    /// (Settings' from macOS 26, whose toolbar draws no band).
    func useAutoHushTitleBar(_ toolbar: NSToolbar, transparent: Bool = true) {
        if transparent { titlebarAppearsTransparent = true }
        titlebarSeparatorStyle = .none
        toolbar.displayMode = .iconOnly
        self.toolbar = toolbar
        toolbarStyle = .unified
    }
}
