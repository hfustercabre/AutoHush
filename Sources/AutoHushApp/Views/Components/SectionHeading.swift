import SwiftUI

/// A small heading over a group of controls: a card, or the menu's buttons.
struct SectionLabel: View {
    let title: Text

    init(_ title: Text) { self.title = title }

    var body: some View {
        title.font(.appCaption).foregroundStyle(.appSecondary)
    }
}

/// A word in a capsule after a heading that qualifies everything under it,
/// e.g. "Experimental" after "Safari Web Apps".
struct HeadingBadge: View {
    /// Already localized.
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.appCaption.weight(.semibold))
            .foregroundStyle(.appWarning)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(.warningBadgeFill))
            .fixedSize()
    }
}

/// The heading over a card in Settings, e.g. "Timing": a section label in
/// line with the card's text, with room above it unless it's the first
/// thing on its tab.
struct SectionHeading: View {
    let title: Text
    var isFirst = false

    init(_ title: Text, isFirst: Bool = false) {
        self.title = title
        self.isFirst = isFirst
    }

    var body: some View {
        SectionLabel(title)
            .padding(.leading, 4)
            .padding(.top, isFirst ? 0 : 6)
            .accessibilityAddTraits(.isHeader)
    }
}
