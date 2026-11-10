import AppKit

/// A scroll view the keys move where nothing in it takes them (the logs'
/// entries, an update's release notes): ↑ and ↓ about two lines, Page Up
/// and Page Down a page, Home and End to the top and the end (KB7, the
/// a11y audit, 2026-11-06; R5 and R6, the user, 2026-11-10: reach every
/// control).
@MainActor
enum ScrollKeys {
    /// How far ↑ or ↓ goes.
    static let line: CGFloat = 40

    /// Scrolls `scrollView` for `key`; `false` for a key it doesn't take,
    /// or ↑ or ↓ already at that end, so the key can go on.
    @discardableResult static func scroll(_ scrollView: NSScrollView, _ key: HighlightKey) -> Bool {
        guard let document = scrollView.documentView else { return false }
        let clip = scrollView.contentView
        let visible = clip.documentVisibleRect
        let range = max(0, document.frame.height - visible.height)
        // From the top, whichever way the document's coordinates go.
        let fromTop = document.isFlipped ? visible.minY : range - visible.minY
        let page = max(visible.height - scrollView.verticalPageScroll, visible.height / 2)
        let target: CGFloat
        switch key {
        case .up:
            guard fromTop > 0.5 else { return false }
            target = fromTop - line
        case .down:
            guard fromTop < range - 0.5 else { return false }
            target = fromTop + line
        case .pageUp: target = fromTop - page
        case .pageDown: target = fromTop + page
        case .home: target = 0
        case .end: target = range
        default: return false
        }
        let clamped = min(max(target, 0), range)
        clip.scroll(to: NSPoint(x: visible.minX, y: document.isFlipped ? clamped : range - clamped))
        scrollView.reflectScrolledClipView(clip)
        return true
    }
}
