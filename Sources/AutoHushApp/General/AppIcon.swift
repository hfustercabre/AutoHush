import AppKit
import AutoHushKit

/// App icons for menus and Settings, cached by bundle path.
@MainActor
enum AppIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for source: AudioSource, size: CGFloat = 16) -> NSImage {
        image(bundlePath: source.bundlePath, size: size)
    }

    /// The icon of the app at `bundlePath`; the generic app icon without one.
    static func image(bundlePath: String?, size: CGFloat = 16) -> NSImage {
        let key = "\(bundlePath ?? "")#\(size)"
        if let cached = cache[key] { return cached }
        let image = (bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)).copy() as! NSImage
        image.size = NSSize(width: size, height: size)
        cache[key] = image
        return image
    }
}
