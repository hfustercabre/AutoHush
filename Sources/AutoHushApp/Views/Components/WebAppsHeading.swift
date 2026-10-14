import SwiftUI

/// Over the Safari web apps wherever players are offered: "Safari Web Apps"
/// with its "Experimental" badge, and the note that every website works
/// differently.
struct WebAppsHeading: View {
    /// The heading's own font: menus draw theirs a little larger than
    /// `SectionLabel`.
    var font: Font = .appCaption

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
            Text(verbatim: PlayerOption.webAppsNote)
                .captionStyle()
        }
    }
}
