import AppKit
import Testing
@testable import AutoHushApp

@Suite("MenuBarIcon")
@MainActor
struct MenuBarIconTests {
    /// Draws an icon at 2× (36 × 36 pixels), optionally over a background colour.
    private func render(_ icon: MenuBarIcon, over background: NSColor? = nil) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = MenuBarIcon.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if let background {
            background.setFill()
            NSRect(origin: .zero, size: MenuBarIcon.size).fill()
        }
        icon.image().draw(in: NSRect(origin: .zero, size: MenuBarIcon.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// The colour at a point of the 18 × 18 pt grid (y pointing down).
    private func color(_ rep: NSBitmapImageRep, at x: CGFloat, _ y: CGFloat) -> NSColor {
        rep.colorAt(x: Int(x * 2), y: Int(y * 2))!.usingColorSpace(.deviceRGB)!
    }

    @Test("every state is an 18 pt template image that describes itself")
    func templateImages() {
        for icon in MenuBarIcon.allCases {
            let image = icon.image(accessibilityDescription: "AutoHush")
            #expect(image.isTemplate)
            #expect(image.size == NSSize(width: 18, height: 18))
            #expect(image.accessibilityDescription == "AutoHush")
        }
    }

    @Test("the bars are cut out of a solid rounded square")
    func cutOutOfTile() {
        let rep = render(.playing)
        #expect(color(rep, at: 3, 3).alphaComponent > 0.9)   // the tile
        #expect(color(rep, at: 9, 9).alphaComponent < 0.1)   // inside the middle bar
        #expect(color(rep, at: 0.4, 0.4).alphaComponent < 0.1) // outside the rounded corner
    }

    @Test("the cut-outs show what is behind the icon, rather than punching through it")
    func cutOutsKeepTheBackground() {
        let rep = render(.playing, over: .red)
        let inBar = color(rep, at: 9, 9)
        #expect(inBar.redComponent > 0.9 && inBar.greenComponent < 0.1)
    }

    @Test("each state looks different")
    func distinctStates() {
        let drawings = MenuBarIcon.allCases.map { render($0).representation(using: .png, properties: [:])! }
        #expect(Set(drawings).count == MenuBarIcon.allCases.count)
    }
}
