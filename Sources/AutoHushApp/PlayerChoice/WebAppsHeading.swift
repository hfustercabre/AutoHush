import AppKit
import SwiftUI

/// Over the Safari web apps wherever players are offered: "Safari Web Apps"
/// with its "Experimental" badge, and the note that every website works
/// differently.
struct WebAppsHeading: View {
    /// The heading's own font: menus draw theirs a little larger than
    /// `SectionLabel`.
    var font: Font = .appCaption
    var showsNote = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(verbatim: PlayerOption.webAppsHeading)
                    .font(font)
                    .foregroundStyle(.appSecondary)
                HeadingBadge(text: PlayerOption.experimentalBadge)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if showsNote {
                Text(verbatim: PlayerOption.webAppsNote)
                    .captionStyle()
            }
        }
    }
}

extension NSMenuItem {
    /// The web apps' heading and note as a menu row (the menu's and the
    /// player pop-up's): a native section header can't show a badge.
    @MainActor
    static func webAppsHeading(width: CGFloat?) -> NSMenuItem {
        let item = NSMenuItem(title: PlayerOption.webAppsHeading, action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier("webAppsHeading")
        item.isEnabled = false
        let heading = WebAppsHeading(font: .system(size: NSFont.systemFontSize(for: .small), weight: .semibold))
            // In line with the rows' icons, as a section header's title is.
            .padding(.leading, menuRowLeading)
            .padding(.trailing, 14)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(width: width, alignment: .leading)
        let hosting = NSHostingView(rootView: heading)
        hosting.frame.size = hosting.fittingSize
        hosting.autoresizingMask = [.width]
        item.view = hosting
        return item
    }

    /// Where a menu row's icon starts, from the menu's edge.
    static let menuRowLeading: CGFloat = 30
}
