import SwiftUI

/// A section's title, as System Settings' (the user, 2026-10-17, H3): bold
/// and primary at body size, outside the group it names: the menu's
/// sections ("Turn off for", "Playing Now", More Settings' pages).
struct SectionLabel: View {
    let title: Text

    init(_ title: Text) { self.title = title }

    var body: some View {
        title.font(.appHeadline).foregroundStyle(.primary)
    }
}

/// A word in a capsule after a heading that qualifies everything under it,
/// e.g. "Experimental" after "Safari Web Apps"; in the accent color for a
/// good word ("Recommended", Add an App's ways), in macOS's own colors.
struct HeadingBadge: View {
    /// Already localized.
    let text: String
    var accent = false

    var body: some View {
        Text(verbatim: text)
            .font(.appCaption.weight(.semibold))
            .foregroundStyle(accent ? AnyShapeStyle(.appAccent) : AnyShapeStyle(.appWarning))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(accent ? AnyShapeStyle(.selectedRowFill) : AnyShapeStyle(.warningBadgeFill)))
            .fixedSize()
    }
}

/// The title over a card in Settings and the other windows, e.g. "Timing",
/// outside it as System Settings' are: a section label in line with the
/// card's text, with room above it unless it's the first thing on its tab.
struct SectionHeading: View {
    let title: Text
    var isFirst = false

    init(_ title: Text, isFirst: Bool = false) {
        self.title = title
        self.isFirst = isFirst
    }

    @Environment(\.cardsAreFormSections) private var isFormHeader

    var body: some View {
        SectionLabel(title)
            // In a form's header it lines up with the other sections' titles.
            .padding(.leading, isFormHeader ? 0 : 4)
            .padding(.top, isFirst ? 0 : 6)
            .accessibilityAddTraits(.isHeader)
    }
}
