import SwiftUI

/// The menu's spacing, in one place: around its parts' titles, rows, lines
/// and controls (STYLE_GUIDE's Menu). Compact, as the user picked (D5 with
/// small switches, 2026-10-18: "The menubar menu feels like it takes too
/// much space without showing that much information").
enum MenuSpacing {
    /// Above a part's title ("Playing Now", "Media Player"), and under it.
    static let titleTop: CGFloat = 4
    static let titleBottom: CGFloat = 0
    /// Above and under a row of a switch or a chevron, and its two lines.
    static let rowVertical: CGFloat = 2
    /// Above and under a line between parts.
    static let lineVertical: CGFloat = 2
    /// Above and under "Turn off for" and "Playing Now", and between their
    /// titles and what's under them.
    static let sectionVertical: CGFloat = 3
    static let snoozeSpacing: CGFloat = 3
    /// Under Playing Now's and Recently Played's titles and between their
    /// rows; under the side window's title too.
    static let playingSpacing: CGFloat = 4
    /// Above and under a duration's text, in its button.
    static let chipVertical: CGFloat = 3
    /// Above and under a bottom button's symbol and title.
    static let toolbarVertical: CGFloat = 3
    /// The menu's switches: macOS's small ones.
    static let switchSize: ControlSize = .small

    /// Where a row's picture starts from the menu's edge, how wide its
    /// column is, and the gap to the row's text (`text`, where the text
    /// starts): the same for every row, so their pictures and text line up
    /// down the menu (I2, the user's pick, 2026-10-18): Playing Now's and
    /// Recently Played's apps, the warnings and the update found, Media
    /// Player's and Ignored Apps' rows.
    struct RowLayout {
        let leading: CGFloat
        let picture: CGFloat
        let gap: CGFloat
        var text: CGFloat { leading + picture + gap }
    }

    static let row = RowLayout(leading: 16, picture: 22, gap: 10)
}
