import SwiftUI

/// "Would you like to support me?" with the Buy me a coffee link under it, in
/// Settings → About and at the foot of Settings' sidebar (`compact`: the
/// question smaller, the cup on the link).
struct SupportLine: View {
    var compact = false

    var body: some View {
        if compact {
            VStack(spacing: 2) {
                question.font(.appCaption).foregroundStyle(.appSecondary)
                Link(destination: ProjectInfo.supportPage) {
                    Label { link } icon: { Image(systemName: "cup.and.saucer") }
                }
                .font(.appCallout)
            }
        } else {
            VStack(spacing: 4) {
                Label { question } icon: { Image(systemName: "cup.and.saucer") }
                    .foregroundStyle(.appSecondary)
                Link(destination: ProjectInfo.supportPage) { link }
            }
            .font(.appCallout)
        }
    }

    private var question: Text {
        Text("Would you like to support me?",
             comment: "Settings → About and Settings' sidebar, before the Buy me a coffee link")
    }

    private var link: Text {
        Text("Buy me a coffee",
             comment: "Link to the developer's Buy Me a Coffee page (Settings → About and Settings' sidebar)")
    }
}
