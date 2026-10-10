import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit

@Suite("AppIcon")
@MainActor
struct AppIconTests {
    /// A red tile with a square mark in its middle: blue, or green on a dark
    /// tile.
    private let placeholder = PlayerIconPlaceholder(
        tile: [.init(0xFF0000)], mark: .init(0x0000FF), darkMark: .init(0x00FF00)
    ) {
        CGPath(rect: CGRect(x: 400, y: 400, width: 200, height: 200), transform: nil)
    }

    /// Draws the placeholder 100 points wide, a pixel per point.
    private func render(dark: Bool) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        AppIcon.image(placeholder: placeholder, id: "com.example.test.\(dark)", size: 100, dark: dark)
            .draw(in: NSRect(x: 0, y: 0, width: 100, height: 100))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// The colour at a point, y pointing down.
    private func color(_ rep: NSBitmapImageRep, at x: Int, _ y: Int) -> NSColor {
        rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    }

    @Test("a placeholder is its mark on a tile in its colors, inside an app icon's margin")
    func defaultStyle() {
        let rep = render(dark: false)
        let mark = color(rep, at: 50, 50)
        #expect(mark.blueComponent > 0.8 && mark.redComponent < 0.2)
        let tile = color(rep, at: 20, 50)
        #expect(tile.redComponent > 0.8 && tile.blueComponent < 0.2)
        #expect(color(rep, at: 3, 50).alphaComponent < 0.1) // the margin
        #expect(color(rep, at: 12, 12).alphaComponent < 0.1) // outside the rounded corner
    }

    @Test("with dark icons, the tile is dark and the mark takes its dark color")
    func darkStyle() {
        let rep = render(dark: true)
        let mark = color(rep, at: 50, 50)
        #expect(mark.greenComponent > 0.8 && mark.redComponent < 0.2)
        let tile = color(rep, at: 20, 50)
        #expect(tile.alphaComponent > 0.9)
        #expect(max(tile.redComponent, tile.greenComponent, tile.blueComponent) < 0.2)
    }

    @Test("icons are dark when the style says so, or follows a dark appearance")
    func iconStyle() {
        #expect(!AppIcon.usesDarkIcons(style: nil, darkAppearance: true))
        #expect(AppIcon.usesDarkIcons(style: "RegularDark", darkAppearance: false))
        #expect(AppIcon.usesDarkIcons(style: "TintedDark", darkAppearance: false))
        #expect(!AppIcon.usesDarkIcons(style: "ClearLight", darkAppearance: true))
        #expect(AppIcon.usesDarkIcons(style: "ClearAutomatic", darkAppearance: true))
        #expect(!AppIcon.usesDarkIcons(style: "ClearAutomatic", darkAppearance: false))
    }

    @Test("a supported player that's no longer where it was found shows its placeholder; another app what macOS gives it")
    func missingApp() {
        let gone = "/Applications/No Such Player.app"
        let player = PlayerOption(bundleID: "com.example.gone", name: "Gone", appURL: nil, iconPlaceholder: placeholder)
        let placeholderIcon = AppIcon.image(placeholder: placeholder, id: player.bundleID, size: 20)
        let source = AudioSource(id: player.bundleID, name: "Gone", bundlePath: gone)
        #expect(AppIcon.image(for: source, players: [player], size: 20) === placeholderIcon)

        // Another app, not a player: as before, macOS's icon for its path.
        let other = AudioSource(id: "com.example.other", name: "Other", bundlePath: gone)
        #expect(AppIcon.image(for: other, players: [player], size: 20) === AppIcon.image(bundlePath: gone, size: 20))
        #expect(AppIcon.image(for: other, players: [player], size: 20) !== placeholderIcon)

        // An app that's there keeps its own icon, even when it's a player.
        let safari = AudioSource(id: player.bundleID, name: "Safari", bundlePath: "/Applications/Safari.app")
        #expect(AppIcon.image(for: safari, players: [player], size: 20) !== placeholderIcon)

        // An installed player isn't looked for on the disk: no placeholder.
        let installed = PlayerOption(bundleID: player.bundleID, name: "Gone", appURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                                     iconPlaceholder: placeholder)
        #expect(AppIcon.image(for: source, players: [installed], size: 20) !== placeholderIcon)
    }
}
