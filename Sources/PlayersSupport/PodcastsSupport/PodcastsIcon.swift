import CoreGraphics
import Foundation
import AutoHushKit

extension PlayerIconPlaceholder {
    /// Apple Podcasts' broadcast mark: a microphone in two arcs, white on its
    /// purple tile, purple on a dark one.
    static let applePodcasts = PlayerIconPlaceholder(
        tile: [RGB(0xD56DFB), RGB(0x832BC1)],
        mark: RGB(0xFFFFFF),
        darkMark: RGB(0xB04DE8)
    ) {
        let center = CGPoint(x: 500, y: 420)
        var mark = CGPath(ellipseIn: CGRect(x: center.x - 78, y: center.y - 78, width: 156, height: 156), transform: nil)
        mark = mark.union(CGPath(roundedRect: CGRect(x: 455, y: 540, width: 90, height: 250),
                                 cornerWidth: 45, cornerHeight: 45, transform: nil))
        // Two arcs open at the bottom, around the microphone's head.
        for radius: CGFloat in [175, 285] {
            let arc = CGMutablePath()
            arc.addArc(center: center, radius: radius, startAngle: .pi * 3 / 4, endAngle: .pi * 9 / 4, clockwise: false)
            mark = mark.union(arc.copy(strokingWithWidth: 52, lineCap: .round, lineJoin: .round, miterLimit: 1))
        }
        return mark
    }
}
