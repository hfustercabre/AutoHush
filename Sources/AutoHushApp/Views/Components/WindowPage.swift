import AppKit
import SwiftUI

/// A window's page (welcome and its permissions page, Add a Web App,
/// learning, Add an App, its list of apps and its warning): its
/// `WindowHeader`, what it shows under it, in the window's margins, then its
/// buttons in a `BottomBar` across the window; `width` wide, in `appBody`.
/// `spacing` is between the header and each part under it; `alignment`
/// lines them up (the welcome window's players page has them centered).
struct WindowPage<Content: View, Bar: View>: View {
    let icon: NSImage?
    let description: Text
    let width: CGFloat
    var alignment = HorizontalAlignment.leading
    var spacing: CGFloat = 8
    let content: Content
    let bar: Bar

    init(icon: NSImage?, description: Text, width: CGFloat, alignment: HorizontalAlignment = .leading, spacing: CGFloat = 8,
         @ViewBuilder content: () -> Content, @ViewBuilder bar: () -> Bar) {
        self.icon = icon
        self.description = description
        self.width = width
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
        self.bar = bar()
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            VStack(alignment: alignment, spacing: spacing) {
                WindowHeader(icon: icon, description: description)
                content
            }
            .windowMargins()
            BottomBar { bar }
        }
        .frame(width: width)
        .font(.appBody)
    }
}

extension View {
    /// A window's content margins: 20 pt, and right under the title bar,
    /// so the header reads with the title. Its `BottomBar` uses the same
    /// side margin.
    func windowMargins() -> some View {
        padding(.top, 2)
            .padding([.horizontal, .bottom], HostedWindowController.margin)
    }
}
