import SwiftUI

/// Over the Safari web apps wherever players are offered: "Safari Web Apps"
/// with its "Experimental" badge, and the note that every website works
/// differently.
struct WebAppsHeading: View {
    var font: Font = .appCaption

    var body: some View {
        BadgedHeading(title: PlayerOption.webAppsHeading, badge: PlayerOption.experimentalBadge,
                      note: PlayerOption.webAppsNote, font: font)
    }
}
