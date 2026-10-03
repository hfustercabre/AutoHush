import AppKit
import AutoHushKit

/// App icons for menus and Settings, cached by bundle path.
@MainActor
enum AppIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for source: AudioSource, size: CGFloat = 16) -> NSImage {
        let key = "\(source.bundlePath ?? "")#\(size)"
        if let cached = cache[key] { return cached }
        let image = (source.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: .application)).copy() as! NSImage
        image.size = NSSize(width: size, height: size)
        cache[key] = image
        return image
    }
}
