import SwiftUI

/// "Would you like to support me?" with the Buy me a coffee link under it, at
/// the foot of Settings' sidebar: the question small, the cup on the link.
struct SupportLine: View {
    var body: some View {
        VStack(spacing: 2) {
            question.font(.appCaption).foregroundStyle(.appSecondary)
            Link(destination: ProjectInfo.supportPage) {
                Label { link } icon: { Image(systemName: "cup.and.saucer") }
            }
            .font(.appCallout)
        }
    }

    private var question: Text {
        Text("Would you like to support me?",
             comment: "At the foot of Settings' sidebar, before the Buy me a coffee link")
    }

    private var link: Text {
        Text("Buy me a coffee",
             comment: "Link to the developer's Buy Me a Coffee page, at the foot of Settings' sidebar")
    }
}
