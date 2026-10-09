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

    /// Shows `name` with a `HeadingBadge` after it ("Untested"), drawn as an
    /// image: a menu item's title can't hold a view. Both fit in `maxWidth`:
    /// a long name is cut short with "…", so the badge always shows.
    @MainActor
    func setTitle(_ name: String, badge: String, font: NSFont, maxWidth: CGFloat) {
        let title = NSMutableAttributedString()
        let dark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let renderer = ImageRenderer(content: HeadingBadge(text: badge).environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let gap = NSAttributedString(string: "  ", attributes: [.font: font])
        let badgeWidth = renderer.nsImage?.size.width ?? (badge as NSString).size(withAttributes: [.font: font]).width
        let room = maxWidth - badgeWidth - gap.size().width
        title.append(NSAttributedString(string: Self.truncated(name, toFit: room, font: font), attributes: [.font: font]))
        if let image = renderer.nsImage {
            image.accessibilityDescription = badge
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CGRect(x: 0, y: (font.capHeight - image.size.height) / 2,
                                       width: image.size.width, height: image.size.height)
            title.append(gap)
            title.append(NSAttributedString(attachment: attachment))
        } else {
            title.append(NSAttributedString(string: "  " + badge, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        attributedTitle = title
        // Set after it, it keeps the badge, and its plain title is the whole
        // name alone (for type-to-select and VoiceOver), not the name and "￼".
        self.title = name
    }

    /// `text`, cut short with "…" to fit `width` in `font`.
    static func truncated(_ text: String, toFit width: CGFloat, font: NSFont) -> String {
        let fits = { (candidate: String) in (candidate as NSString).size(withAttributes: [.font: font]).width <= width }
        guard !fits(text) else { return text }
        var low = 0
        var high = text.count
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(String(text.prefix(middle)) + "…") { low = middle } else { high = middle - 1 }
        }
        return String(text.prefix(low)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
