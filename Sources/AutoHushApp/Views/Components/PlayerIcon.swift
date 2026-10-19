import AppKit
import SwiftUI

/// The chosen media player's icon, `size` pt square, faded while it isn't
/// installed; AutoHush's own while none is chosen: the menu's card (36 pt),
/// its Media Player row (22 pt) and Settings → General (56 pt).
struct PlayerIcon: View {
    let player: PlayerOption?
    let size: CGFloat

    var body: some View {
        Image(nsImage: player?.icon(size: size) ?? NSApp.applicationIconImage ?? AppIcon.image(bundlePath: nil, size: size))
            .resizable()
            .frame(width: size, height: size)
            .opacity(player?.isInstalled == false ? 0.5 : 1)
            .accessibilityHidden(true)
    }
}
