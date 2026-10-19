import SwiftUI

/// The buttons at the foot of a window (welcome, Add a Web App, learning,
/// Add an App and its own, the logs) or of a Settings page whose list
/// scrolls (Sound Sources, Diagnostics), with a line above them while the
/// content runs under them. `margin`: the side margin the buttons line up
/// with: a window's (`windowMargins`), which macOS's grouped form insets
/// its sections by too.
struct BottomBar<Content: View>: View {
    var margin = HostedWindowController.margin
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack { content }
                .padding(.horizontal, margin)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
    }
}
