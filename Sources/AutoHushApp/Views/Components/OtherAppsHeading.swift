import SwiftUI

/// Over the apps added through a check wherever players are offered (E3,
/// the user's pick, 2026-10-15): "Other Apps" with its "Checked by you"
/// badge, and the note that they're controlled the ways a check found.
struct OtherAppsHeading: View {
    var font: Font = .appCaption

    var body: some View {
        BadgedHeading(title: PlayerOption.otherAppsHeading, badge: PlayerOption.checkedByYouBadge,
                      note: PlayerOption.otherAppsNote, font: font)
    }
}
