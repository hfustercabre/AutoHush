import SwiftUI

/// A heading over a group of players with a badge after it and a note under
/// it, wherever players are offered: "Other Apps" (Checked by you) and
/// "Safari Web Apps" (Experimental).
struct BadgedHeading: View {
    let title: String
    /// None while there's nothing for it to qualify.
    let badge: String?
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                SectionLabel(Text(verbatim: title))
                if let badge { HeadingBadge(text: badge) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(verbatim: note)
                .captionStyle()
        }
    }
}
