import AppKit
import SwiftUI

/// Lays `view` out and draws it `width` wide, as its window would, off
/// screen: a view that can't be drawn (an environment value it needs
/// missing, a row past its list's end) fails the test that draws it. Its
/// size, as it fits.
@MainActor
func drawn(_ view: some View, width: CGFloat) -> NSSize {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: 600)
    hosting.layoutSubtreeIfNeeded()
    if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    }
    return hosting.fittingSize
}
