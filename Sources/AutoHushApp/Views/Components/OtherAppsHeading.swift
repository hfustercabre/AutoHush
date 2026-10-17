import SwiftUI

/// Over the apps added through a check wherever players are offered (E3,
/// the user's pick, 2026-10-15): "Other Apps" with its "Checked by you"
/// badge, and the note that they're controlled the ways a check found.
/// While none was added, no badge, and the note says what Add… does
/// (2026-10-16), so it doesn't read as if some were checked.
struct OtherAppsHeading: View {
    var isEmpty = false

    var body: some View {
        BadgedHeading(title: PlayerOption.otherAppsHeading, badge: isEmpty ? nil : PlayerOption.checkedByYouBadge,
                      note: isEmpty ? PlayerOption.otherAppsEmptyNote : PlayerOption.otherAppsNote)
    }
}
