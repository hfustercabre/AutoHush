import CoreGraphics
import Foundation

/// What is read of a window `CGWindowListCopyWindowInfo` lists, read once
/// and the same way wherever windows are read: its owner, layer, frame and
/// the rest need no Screen Recording.
package struct ListedWindow: Sendable {
    /// The process that owns it; `nil` when it isn't said.
    package let owner: pid_t?
    /// 0 (ordinary windows) when it isn't said.
    package let layer: Int
    /// `nil` when it isn't said, or can't be read.
    package let frame: CGRect?
    /// 1 when it isn't said.
    package let alpha: Double
    /// Whether it's on screen: not when it isn't said.
    package let isOnScreen: Bool
    /// Its number with the window server; 0 when it isn't said.
    package let number: Int

    package init(_ info: [String: Any]) {
        owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        frame = (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
    }
}
