import CoreGraphics
import AutoHushKit

extension PlayerIconPlaceholder {
    /// VLC's traffic cone: orange, with two stripes, on a light tile.
    static let vlc = PlayerIconPlaceholder(
        tile: [RGB(0xFFFFFF), RGB(0xE9E9E9)],
        mark: RGB(0xFF8800)
    ) {
        let body = CGMutablePath()
        body.addLines(between: [
            CGPoint(x: 468, y: 190), CGPoint(x: 532, y: 190), CGPoint(x: 700, y: 745), CGPoint(x: 300, y: 745),
        ])
        body.closeSubpath()
        let tip = CGPath(ellipseIn: CGRect(x: 462, y: 160, width: 76, height: 76), transform: nil)
        let stripes = CGMutablePath()
        stripes.addRect(CGRect(x: 0, y: 385, width: 1000, height: 72))
        stripes.addRect(CGRect(x: 0, y: 565, width: 1000, height: 72))
        let base = CGPath(roundedRect: CGRect(x: 205, y: 745, width: 590, height: 90), cornerWidth: 34, cornerHeight: 34, transform: nil)
        return body.union(tip).subtracting(stripes).union(base)
    }
}
