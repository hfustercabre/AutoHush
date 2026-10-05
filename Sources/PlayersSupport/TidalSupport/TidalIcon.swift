import CoreGraphics
import AutoHushKit

extension PlayerIconPlaceholder {
    /// TIDAL's four diamonds, white on its black tile: three in a row and
    /// one under the middle, touching at their corners.
    static let tidal = PlayerIconPlaceholder(tile: [RGB(0x000000)], mark: RGB(0xFFFFFF)) {
        let half: CGFloat = 95 // half a diamond's width
        let mark = CGMutablePath()
        for (column, row) in [(-1, 0), (0, 0), (1, 0), (0, 1)] {
            // The four of them, centred on the tile.
            let center = CGPoint(x: 500 + CGFloat(column) * 2 * half, y: 500 - half + CGFloat(row) * 2 * half)
            mark.addLines(between: [
                CGPoint(x: center.x, y: center.y - half), CGPoint(x: center.x + half, y: center.y),
                CGPoint(x: center.x, y: center.y + half), CGPoint(x: center.x - half, y: center.y),
            ])
            mark.closeSubpath()
        }
        return mark
    }
}
