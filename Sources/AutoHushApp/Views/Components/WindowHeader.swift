import AppKit
import SwiftUI

/// The top of a window AutoHush opens (welcome and its permissions page, Add
/// a Web App, learning, Add an App, its list of apps and its warning; atop
/// its `WindowPage`): an icon, then what the window is for. The window's
/// title is in its title bar, as a Settings page's name is
/// (`HostedWindowController`).
struct WindowHeader: View {
    let icon: NSImage?
    let description: Text

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
            }
            description
                .foregroundStyle(.appSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
