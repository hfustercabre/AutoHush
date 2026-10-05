import CoreGraphics
import AutoHushKit

extension PlayerIconPlaceholder {
    /// Apple Music's beamed notes: white on its red tile, red on a dark one.
    static let appleMusic = PlayerIconPlaceholder(
        tile: [RGB(0xFB5C74), RGB(0xFA233B)],
        mark: RGB(0xFFFFFF),
        darkMark: RGB(0xF02540)
    ) {
        // Measured on Music's icon: a thick beam rising to the right, two
        // thin stems, and tilted heads at their feet.
        let beam = CGMutablePath()
        beam.addLines(between: [
            CGPoint(x: 364, y: 223), CGPoint(x: 738, y: 136), CGPoint(x: 738, y: 301), CGPoint(x: 364, y: 379),
        ])
        beam.closeSubpath()
        var note = beam as CGPath
        for (stem, head) in [
            (CGRect(x: 364, y: 300, width: 39, height: 440), CGPoint(x: 303, y: 738)),
            (CGRect(x: 699, y: 200, width: 39, height: 465), CGPoint(x: 643, y: 665)),
        ] {
            var tilt = CGAffineTransform(translationX: head.x, y: head.y).rotated(by: -25 * .pi / 180)
            let oval = CGPath(ellipseIn: CGRect(x: -100, y: -88, width: 200, height: 176), transform: &tilt)
            note = note.union(CGPath(rect: stem, transform: nil)).union(oval)
        }
        return note
    }
}
