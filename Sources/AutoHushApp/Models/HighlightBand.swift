import Foundation

/// The part of a window a highlightable control is in, top to bottom: the
/// keys go through one before the next. In the menu, the card is pinned
/// over what scrolls and the buttons under it; in Settings → Sound Sources,
/// the heading over the apps' list and the buttons under it.
enum HighlightBand: Int, Comparable {
    case top, middle, bottom

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
