// Draws the background of the DMG window: the AutoHush mark and name, an
// arrow from the app to the Applications folder, and a note about the first
// launch, on the lavender of the light app icon.
//
// Built together with the app's MenuBarIcon.swift, so the mark is the real
// menu bar icon (see build-dmg.sh):
//   swiftc -parse-as-library Sources/AutoHushApp/MenuBar/MenuBarIcon.swift \
//       Scripts/lib/dmg-background.swift -o dmg-background
//   dmg-background <output.png> <scale>
//
// The window is 640 × 480 points; scale 2 renders it for Retina displays.
// Everything sits in the top 400 points: the rest is room for Finder's tab
// and path bars, which some people show in every window. Icon centres (in
// points, from the top left) must match build-dmg.sh.
import AppKit

@main
enum DMGBackground {
    static let size = NSSize(width: 640, height: 480)
    static let appIconCenter = NSPoint(x: 170, y: 200)
    static let applicationsCenter = NSPoint(x: 470, y: 200)

    static let purple = NSColor(srgbRed: 0.431, green: 0.357, blue: 0.839, alpha: 1)  // the app icon's bars
    static let ink = NSColor(srgbRed: 0.169, green: 0.141, blue: 0.388, alpha: 1)     // titles
    static let muted = NSColor(srgbRed: 0.373, green: 0.369, blue: 0.541, alpha: 1)   // other text

    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 3, let scale = Double(arguments[2]) else {
            fail("usage: dmg-background <output.png> <scale>")
        }
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { fail("could not create the bitmap") }
        bitmap.size = size // points; the pixel size carries the scale

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        drawBackground()
        drawHeader()
        drawArrow()
        drawFirstLaunchNote()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else { fail("could not encode the PNG") }
        do {
            try png.write(to: URL(fileURLWithPath: arguments[1]))
        } catch {
            fail("could not write \(arguments[1]): \(error.localizedDescription)")
        }
    }

    // MARK: - Parts

    /// The light app icon's lavender, fading down; dark enough nowhere for
    /// Finder's black icon labels to suffer.
    private static func drawBackground() {
        let top = NSColor(srgbRed: 0.984, green: 0.980, blue: 1.0, alpha: 1)
        let bottom = NSColor(srgbRed: 0.933, green: 0.922, blue: 0.984, alpha: 1)
        NSGradient(starting: top, ending: bottom)!.draw(in: NSRect(origin: .zero, size: size), angle: -90)
    }

    /// The menu bar mark in purple beside the name, centred, and what to do.
    private static func drawHeader() {
        let mark: CGFloat = 30, gap: CGFloat = 10
        let name = NSAttributedString(string: "AutoHush", attributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: ink,
        ])
        let nameSize = name.size()
        let left = (size.width - mark - gap - nameSize.width) / 2
        let centerY = size.height - 54
        tinted(MenuBarIcon.playing.image(), purple)
            .draw(in: NSRect(x: left, y: centerY - mark / 2, width: mark, height: mark))
        name.draw(at: NSPoint(x: left + mark + gap, y: centerY - nameSize.height / 2))

        drawCentered("Drag AutoHush into Applications to install it", atTop: 86,
                     font: .systemFont(ofSize: 14), color: muted)
    }

    /// From the app to the Applications folder, between the 112 pt icons.
    private static func drawArrow() {
        let y = size.height - appIconCenter.y
        let start = NSPoint(x: appIconCenter.x + 82, y: y)
        let tip = NSPoint(x: applicationsCenter.x - 72, y: y)
        purple.setStroke()
        let arrow = NSBezierPath()
        arrow.lineWidth = 5
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.move(to: start)
        arrow.line(to: tip)
        arrow.move(to: NSPoint(x: tip.x - 16, y: y + 14))
        arrow.line(to: tip)
        arrow.line(to: NSPoint(x: tip.x - 16, y: y - 14))
        arrow.stroke()
    }

    /// The app isn't notarized, so the first launch needs one confirmation.
    private static func drawFirstLaunchNote() {
        let card = NSRect(x: 110, y: size.height - 380, width: size.width - 220, height: 54)
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12).fill()
        drawCentered(
            "First launch: if macOS says it can't open AutoHush, go to\nSystem Settings → Privacy & Security → Open Anyway (only once).",
            atTop: size.height - card.maxY + 11, font: .systemFont(ofSize: 12), color: muted
        )
    }

    // MARK: - Helpers

    private static func drawCentered(_ text: String, atTop top: CGFloat, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        let string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ])
        let height = string.boundingRect(with: NSSize(width: size.width - 80, height: 200),
                                         options: [.usesLineFragmentOrigin]).height
        string.draw(with: NSRect(x: 40, y: size.height - top - height, width: size.width - 80, height: height),
                    options: [.usesLineFragmentOrigin])
    }

    /// A template image filled with one colour.
    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(1)
    }
}
