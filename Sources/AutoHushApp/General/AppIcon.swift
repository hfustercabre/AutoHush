import AppKit
import SwiftUI
import AutoHushKit

/// App icons for menus and Settings, cached by bundle path.
@MainActor
enum AppIcon {
    private static var cache: [String: NSImage] = [:]

    /// An app that played audio, as the lists show it: its icon, or, once a
    /// supported player is no longer where it was found, its placeholder
    /// (`players`).
    static func image(for source: AudioSource, players: [PlayerOption] = [], size: CGFloat = 16) -> NSImage {
        image(bundlePath: source.bundlePath, id: source.id, players: players, size: size)
    }

    /// The icon of the app at `bundlePath`; the generic app icon without one.
    /// When the app is a supported player (its bundle ID `id` is among
    /// `players`) that isn't installed and isn't there, its placeholder, as
    /// wherever players are offered: the disk is looked at only then. Another
    /// app that was deleted shows what macOS gives it.
    static func image(bundlePath: String?, id: String? = nil, players: [PlayerOption] = [], size: CGFloat = 16) -> NSImage {
        if let id, let player = players.first(where: { $0.bundleID == id }), !player.isInstalled,
           let placeholder = player.iconPlaceholder,
           !(bundlePath.map { FileManager.default.fileExists(atPath: $0) } ?? false) {
            return image(placeholder: placeholder, id: id, size: size)
        }
        let key = "\(bundlePath ?? "")#\(size)"
        if let cached = cache[key] { return cached }
        let image = (bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)).copy() as! NSImage
        image.size = NSSize(width: size, height: size)
        cache[key] = image
        return image
    }

    /// A stand-in for the icon of a player that isn't installed, `id` being
    /// its bundle ID: drawn like an app icon, dark or in its colors.
    static func image(placeholder: PlayerIconPlaceholder, id: String, size: CGFloat, dark: Bool = usesDarkIcons) -> NSImage {
        let key = "placeholder:\(id)#\(size)#\(dark)"
        if let cached = cache[key] { return cached }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(placeholder, dark: dark, in: rect, context: context)
            return true
        }
        cache[key] = image
        return image
    }

    /// Whether app icons are dark, as chosen in System Settings → Appearance.
    static var usesDarkIcons: Bool {
        usesDarkIcons(style: UserDefaults.standard.string(forKey: "AppleIconAppearanceTheme"),
                      darkAppearance: NSApplication.shared.effectiveAppearance.isDark)
    }

    /// Whether app icons are dark, from the icon style's setting, e.g.
    /// "RegularDark" or "ClearAutomatic" (dark while macOS is). macOS doesn't
    /// document it: without one it can read, the style is the default.
    nonisolated static func usesDarkIcons(style: String?, darkAppearance: @autoclosure () -> Bool) -> Bool {
        guard let style else { return false }
        if style.hasSuffix("Dark") { return true }
        return style.hasSuffix("Automatic") && darkAppearance()
    }

    /// On Apple's grid for app icons: an 824-point tile with 185-point
    /// corners, centred in 1024 points.
    private static func draw(_ placeholder: PlayerIconPlaceholder, dark: Bool, in rect: CGRect, context: CGContext) {
        let side = rect.width * 824 / 1024
        let tile = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        context.addPath(RoundedRectangle(cornerRadius: side * 185 / 824, style: .continuous).path(in: tile).cgPath)
        context.clip()

        // Dark icons all share the system's dark tile.
        let colors = dark ? darkTile : placeholder.tile.map(\.cgColor)
        if colors.count > 1, let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil) {
            context.drawLinearGradient(gradient, start: CGPoint(x: tile.midX, y: tile.minY),
                                       end: CGPoint(x: tile.midX, y: tile.maxY), options: [])
        } else if let color = colors.first {
            context.setFillColor(color)
            context.fill(tile)
        }

        context.translateBy(x: tile.minX, y: tile.minY)
        context.scaleBy(x: side / PlayerIconPlaceholder.tileSide, y: side / PlayerIconPlaceholder.tileSide)
        context.addPath(placeholder.markShape())
        context.setFillColor((dark ? placeholder.darkMark : placeholder.mark).cgColor)
        context.fillPath()
    }

    /// The tile of dark app icons, from top to bottom, as macOS draws it.
    private static let darkTile = [PlayerIconPlaceholder.RGB(0x262626).cgColor, PlayerIconPlaceholder.RGB(0x101010).cgColor]
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
