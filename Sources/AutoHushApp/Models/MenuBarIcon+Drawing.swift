import AppKit

/// The icon of each state, drawn in code.
extension MenuBarIcon {
    /// The image's size; the tile fills it.
    static let size = NSSize(width: 17, height: 17)
    /// The image's size with the update badge: as tall as a menu bar item
    /// can be, the tile centered in it as without the badge, so the badge
    /// takes the room around it.
    static let updateSize = NSSize(width: 22, height: 22)

    /// The icon; with `showsUpdate`, the update badge in its corner.
    func image(accessibilityDescription: String? = nil, showsUpdate: Bool = false) -> NSImage {
        let size = showsUpdate ? Self.updateSize : Self.size
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            guard showsUpdate else {
                draw(in: context)
                return true
            }
            // One layer, so the badge's gap cuts the tile and nothing under it.
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.saveGState()
            context.translateBy(x: (size.width - Self.size.width) / 2, y: (size.height - Self.size.height) / 2)
            draw(in: context)
            context.restoreGState()
            Self.drawUpdateBadge(in: context)
            context.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    // MARK: - Drawing (on an 18-unit design grid, y pointing down)

    /// The rounded square the bars are cut out of.
    private static let tile = CGRect(x: 1.2, y: 1.2, width: 15.6, height: 15.6)
    private static let tileCornerRadius: CGFloat = 4.2
    /// The bars are drawn at this scale, centred on the grid, so they sit
    /// inside the tile with room around them.
    private static let glyphScale: CGFloat = 0.82

    private func draw(in context: CGContext) {
        // The design grid, scaled so the tile fills the image.
        let scale = Self.size.width / Self.tile.width
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -Self.tile.minX, y: -Self.tile.minY)

        // A transparency layer keeps the cut-outs inside the tile, rather
        // than through whatever the icon is drawn on.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(.black)
        context.addPath(CGPath(
            roundedRect: Self.tile, cornerWidth: Self.tileCornerRadius, cornerHeight: Self.tileCornerRadius, transform: nil
        ))
        context.fillPath()

        context.setBlendMode(.destinationOut)
        context.setStrokeColor(.black)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let center = Self.tile.midX
        context.translateBy(x: center, y: center)
        context.scaleBy(x: Self.glyphScale, y: Self.glyphScale)
        context.translateBy(x: -center, y: -center)
        for cutout in cutouts { cutout.draw(in: context) }
        context.endTransparencyLayer()
    }

    /// An update waits: a disc with a down arrow cut out of it, in the
    /// bottom-right corner of `updateSize`, half in the room around the
    /// tile, with a gap cut out of the tile around it.
    private static func drawUpdateBadge(in context: CGContext) {
        let center = CGPoint(x: 18, y: 18)
        let radius: CGFloat = 4, gap: CGFloat = 1.2
        func disc(_ radius: CGFloat) {
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }
        context.setFillColor(.black)
        context.setBlendMode(.destinationOut)
        disc(radius + gap)
        context.setBlendMode(.normal)
        disc(radius)

        context.setBlendMode(.destinationOut)
        context.setStrokeColor(.black)
        context.setLineWidth(1.25)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let stem: CGFloat = 2.3, head: CGFloat = 1.7
        context.move(to: CGPoint(x: center.x, y: center.y - stem))
        context.addLine(to: CGPoint(x: center.x, y: center.y + stem))
        context.move(to: CGPoint(x: center.x - head, y: center.y + stem - head))
        context.addLine(to: CGPoint(x: center.x, y: center.y + stem))
        context.addLine(to: CGPoint(x: center.x + head, y: center.y + stem - head))
        context.strokePath()
        context.setBlendMode(.normal)
    }

    /// What each state cuts out of the tile, on the design grid.
    private var cutouts: [Cutout] {
        switch self {
        case .playing:
            return [.bar(left: 2.6, height: 8), .bar(left: 7.8, height: 12), .bar(left: 13, height: 6)]
        case .pausedForApp:
            return [.bar(left: 2.6, height: 2.4), .bar(left: 7.8, height: 11), .bar(left: 13, height: 11)]
        case .noMusic:
            return [.bar(left: 2.6, height: 2.4), .bar(left: 7.8, height: 2.4), .bar(left: 13, height: 2.4)]
        case .elsewhere:
            return [.bar(left: 1.8, height: 5, width: 2.2), .bar(left: 5.8, height: 7.5, width: 2.2), .arrowOut]
        case .starting:
            return [.hollowBar(left: 2.6, height: 8), .hollowBar(left: 7.8, height: 12), .hollowBar(left: 13, height: 6)]
        case .attention:
            return [.bar(left: 2.6, height: 6), .bar(left: 7.8, height: 9), .exclamationMark]
        }
    }

    private enum Cutout {
        /// A rounded bar standing on the baseline.
        case bar(left: CGFloat, height: CGFloat, width: CGFloat = 2.4)
        /// The outline of a bar.
        case hollowBar(left: CGFloat, height: CGFloat)
        /// An arrow pointing up and out, at the right.
        case arrowOut
        /// An exclamation mark, at the right.
        case exclamationMark

        /// The line every bar stands on.
        private static let baseline: CGFloat = 15

        func draw(in context: CGContext) {
            switch self {
            case .bar(let left, let height, let width):
                context.addPath(Self.bar(left: left, height: height, width: width))
                context.fillPath()
            case .hollowBar(let left, let height):
                context.setLineWidth(1.1)
                context.addPath(Self.bar(left: left, height: height, width: 2.4))
                context.strokePath()
            case .arrowOut:
                context.setLineWidth(1.6)
                context.move(to: CGPoint(x: 10.8, y: 9.4))
                context.addLine(to: CGPoint(x: 15.6, y: 4.6))
                context.move(to: CGPoint(x: 12, y: 4.4))
                context.addLine(to: CGPoint(x: 15.8, y: 4.4))
                context.addLine(to: CGPoint(x: 15.8, y: 8.2))
                context.strokePath()
            case .exclamationMark:
                context.setLineWidth(2)
                context.move(to: CGPoint(x: 14.4, y: 4))
                context.addLine(to: CGPoint(x: 14.4, y: 10.4))
                context.strokePath()
                context.fillEllipse(in: CGRect(x: 13.2, y: 12.6, width: 2.4, height: 2.4))
            }
        }

        private static func bar(left: CGFloat, height: CGFloat, width: CGFloat) -> CGPath {
            let rect = CGRect(x: left, y: baseline - height, width: width, height: height)
            return CGPath(roundedRect: rect, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil)
        }
    }
}
