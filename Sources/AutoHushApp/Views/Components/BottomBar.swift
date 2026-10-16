import SwiftUI

/// The buttons at the foot of a Settings page whose list scrolls (Apps,
/// Diagnostics) or of a window (welcome, Add a Web App, learning): a line
/// above them while the content runs under them. `margin`: the page's or
/// window's side margin, which the buttons line up with.
struct BottomBar<Content: View>: View {
    var showsDivider = true
    var margin: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider { Divider() }
            HStack { content }
                .padding(.horizontal, margin)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
    }
}
