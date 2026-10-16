import CoreGraphics
import AutoHushKit

extension PlayerIconPlaceholder {
    /// QuickTime's Q: a blue ring with its tail, on a light tile.
    static let quickTime = PlayerIconPlaceholder(
        tile: [RGB(0xFFFFFF), RGB(0xE9E9E9)],
        mark: RGB(0x1A8CFF)
    ) {
        let outer = CGPath(ellipseIn: CGRect(x: 108, y: 90, width: 730, height: 730), transform: nil)
        let inner = CGPath(ellipseIn: CGRect(x: 250, y: 232, width: 446, height: 446), transform: nil)
        let line = CGMutablePath()
        line.move(to: CGPoint(x: 500, y: 485))
        line.addLine(to: CGPoint(x: 830, y: 815))
        let tail = line.copy(strokingWithWidth: 130, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return outer.subtracting(inner).union(tail)
    }
}
