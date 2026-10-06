import SwiftUI

/// "Would you like to support me?" with the Buy me a coffee link under it, at
/// the foot of Settings → General and → About.
struct SupportLine: View {
    var body: some View {
        VStack(spacing: 4) {
            Label {
                Text("Would you like to support me?",
                     comment: "Settings → About and → General, before the Buy me a coffee link")
            } icon: {
                Image(systemName: "cup.and.saucer")
            }
            .foregroundStyle(.appSecondary)
            Link(destination: ProjectInfo.supportPage) {
                Text("Buy me a coffee",
                     comment: "Link to the developer's Buy Me a Coffee page (Settings → About and → General)")
            }
        }
        .font(.appCallout)
    }
}
