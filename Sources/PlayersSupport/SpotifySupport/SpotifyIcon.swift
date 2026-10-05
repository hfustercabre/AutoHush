import CoreGraphics
import AutoHushKit

extension PlayerIconPlaceholder {
    /// Spotify's green circle with its three sound waves, on its black tile.
    static let spotify = PlayerIconPlaceholder(tile: [RGB(0x121212)], mark: RGB(0x1ED760)) {
        let circle = CGPath(ellipseIn: CGRect(x: 100, y: 100, width: 800, height: 800), transform: nil)
        // Each wave's ends, the point it bends towards and its thickness,
        // measured on Spotify's icon: the waves narrow downwards and lean
        // to the right.
        let waves: [(start: CGPoint, bend: CGPoint, end: CGPoint, width: CGFloat)] = [
            (CGPoint(x: 265, y: 371), CGPoint(x: 518, y: 321), CGPoint(x: 770, y: 442), 72),
            (CGPoint(x: 277, y: 502), CGPoint(x: 493, y: 456), CGPoint(x: 709, y: 558), 58),
            (CGPoint(x: 291, y: 621), CGPoint(x: 486, y: 578), CGPoint(x: 680, y: 672), 46),
        ]
        let cuts = CGMutablePath()
        for wave in waves {
            let line = CGMutablePath()
            line.move(to: wave.start)
            line.addQuadCurve(to: wave.end, control: wave.bend)
            cuts.addPath(line.copy(strokingWithWidth: wave.width, lineCap: .round, lineJoin: .round, miterLimit: 1))
        }
        return circle.subtracting(cuts)
    }
}
