import AppKit
import ApplicationServices

/// macOS's Zoom told where the keys' highlight is (`KeyHighlight`), so a
/// magnified screen follows it as it follows the keyboard's focus (A3,
/// 2026-11-01): the highlight isn't the focus, so Zoom can't see it moving.
enum ZoomFocus {
    /// Shows `rect` (`screenRect`'s coordinates) in Zoom's view, while Zoom is on.
    @MainActor static func follow(_ rect: CGRect) {
        guard UAZoomEnabled() else { return }
        var rect = rect
        _ = UAZoomChangeFocus(&rect, nil, UAZoomChangeFocusType(kUAZoomFocusTypeOther))
    }

    /// `rect`, in `view`'s own coordinates (a hosting view's, as SwiftUI's
    /// `.global` frames are), on the screen as Zoom takes it: from the top
    /// left of the main display, y downwards. `nil` out of a window.
    @MainActor static func screenRect(of rect: CGRect, in view: NSView) -> CGRect? {
        guard let window = view.window, let top = NSScreen.screens.first?.frame.maxY else { return nil }
        let onScreen = window.convertToScreen(view.convert(rect, to: nil))
        return CGRect(x: onScreen.minX, y: top - onScreen.maxY, width: onScreen.width, height: onScreen.height)
    }
}
