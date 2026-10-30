import AppKit
import SwiftUI

/// Lays `view` out and draws it `width` wide, as its window would, off
/// screen: a view that can't be drawn (an environment value it needs
/// missing, a row past its list's end) fails the test that draws it. Its
/// size, as it fits. `height`: tall enough for a form's rows, which are
/// drawn only once in sight.
@MainActor
package func drawn(_ view: some View, width: CGFloat, height: CGFloat = 600) -> NSSize {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    hosting.layoutSubtreeIfNeeded()
    if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    }
    return hosting.fittingSize
}
