import SwiftUI

/// A heading over a group of players with a badge after it and a note under
/// it, wherever players are offered: "Other Apps" (Checked by you) and
/// "Safari Web Apps" (Experimental).
struct BadgedHeading: View {
    let title: String
    /// None while there's nothing for it to qualify.
    let badge: String?
    let note: String
    /// The heading's own font: menus draw theirs a little larger than
    /// `SectionLabel`.
    var font: Font = .appCaption

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(verbatim: title)
                    .font(font)
                    .foregroundStyle(.appSecondary)
                if let badge { HeadingBadge(text: badge) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(verbatim: note)
                .captionStyle()
        }
    }
}
