import CoreGraphics

/// A stand-in for a player's app icon, shown while the app isn't installed
/// and macOS has no icon for it: the player's mark on a tile in its colors.
/// It only has to make the player recognizable, not match its icon.
package struct PlayerIconPlaceholder: Sendable {
    /// An sRGB color, e.g. `RGB(0x1ED760)`.
    package struct RGB: Sendable, Equatable {
        package let red, green, blue: CGFloat

        package init(_ hex: UInt32) {
            red = CGFloat((hex >> 16) & 0xFF) / 255
            green = CGFloat((hex >> 8) & 0xFF) / 255
            blue = CGFloat(hex & 0xFF) / 255
        }

        package var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    }

    /// The tile's colors in the default icon style, from top to bottom; one
    /// for a flat tile.
    package let tile: [RGB]
    /// The mark's color on that tile.
    package let mark: RGB
    /// The mark's color in the dark icon style, where every tile is dark.
    package let darkMark: RGB
    /// The mark, on a tile of side `tileSide` with y pointing down.
    package let markShape: @Sendable () -> CGPath
    /// The side of the tile marks are drawn on: large, since Core Graphics
    /// flattens curves to about half a unit.
    package static let tileSide: CGFloat = 1000

    package init(tile: [RGB], mark: RGB, darkMark: RGB? = nil, markShape: @escaping @Sendable () -> CGPath) {
        self.tile = tile
        self.mark = mark
        self.darkMark = darkMark ?? mark
        self.markShape = markShape
    }
}
