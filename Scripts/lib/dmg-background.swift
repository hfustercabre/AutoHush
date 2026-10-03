// Draws the background of the DMG window: a title, an arrow from the app to
// the Applications folder, and a note about the first launch.
//
// Usage: swift Scripts/lib/dmg-background.swift <output.png> <scale>
// The window is 640×400 points; scale 2 renders it for Retina displays.
// Icon centres (in points, from the top left) must match build-dmg.sh.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let scale = Double(arguments[2]) else {
    FileHandle.standardError.write("usage: dmg-background.swift <output.png> <scale>\n".data(using: .utf8)!)
    exit(64)
}
let outputURL = URL(fileURLWithPath: arguments[1])

let size = NSSize(width: 640, height: 400)
let appIconCenter = NSPoint(x: 170, y: 190)
let applicationsCenter = NSPoint(x: 470, y: 190)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
bitmap.size = size // points; the pixel size carries the scale

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

/// Converts a point measured from the top left (like Finder icon positions)
/// to AppKit's bottom-left origin.
func flipped(_ point: NSPoint) -> NSPoint { NSPoint(x: point.x, y: size.height - point.y) }

func drawCentered(_ text: String, atTop top: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    let string = NSAttributedString(string: text, attributes: attributes)
    let height = string.boundingRect(with: NSSize(width: size.width - 80, height: 200),
                                     options: [.usesLineFragmentOrigin]).height
    string.draw(with: NSRect(x: 40, y: size.height - top - height, width: size.width - 80, height: height),
                options: [.usesLineFragmentOrigin])
}

// Background: a soft vertical gradient, light enough for black icon labels.
NSGradient(starting: NSColor(white: 0.985, alpha: 1), ending: NSColor(white: 0.93, alpha: 1))!
    .draw(in: NSRect(origin: .zero, size: size), angle: -90)

drawCentered("Drag AutoHush into Applications", atTop: 42,
             font: .systemFont(ofSize: 20, weight: .semibold), color: NSColor(white: 0.15, alpha: 1))

// Arrow between the two icons (icons are 112 pt wide).
let arrowStart = flipped(NSPoint(x: appIconCenter.x + 80, y: appIconCenter.y))
let arrowEnd = flipped(NSPoint(x: applicationsCenter.x - 80, y: applicationsCenter.y))
let arrowColor = NSColor(white: 0.55, alpha: 1)
arrowColor.setStroke()
arrowColor.setFill()
let shaft = NSBezierPath()
shaft.lineWidth = 5
shaft.lineCapStyle = .round
shaft.move(to: arrowStart)
shaft.line(to: NSPoint(x: arrowEnd.x - 14, y: arrowEnd.y))
shaft.stroke()
let head = NSBezierPath()
head.move(to: arrowEnd)
head.line(to: NSPoint(x: arrowEnd.x - 22, y: arrowEnd.y + 14))
head.line(to: NSPoint(x: arrowEnd.x - 22, y: arrowEnd.y - 14))
head.close()
head.fill()

drawCentered(
    "First launch: if macOS says it can't open AutoHush, go to\nSystem Settings → Privacy & Security and click Open Anyway (only once).",
    atTop: 318, font: .systemFont(ofSize: 12), color: NSColor(white: 0.35, alpha: 1)
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: outputURL)
} catch {
    FileHandle.standardError.write("could not write \(outputURL.path): \(error)\n".data(using: .utf8)!)
    exit(1)
}
