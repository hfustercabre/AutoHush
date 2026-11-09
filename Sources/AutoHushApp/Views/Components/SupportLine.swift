import SwiftUI

/// "Would you like to support me?" with the Buy me a coffee link under it, at
/// the foot of Settings' sidebar: the question small, the cup on the link.
/// The arrow keys and the pointer highlight the link, as the sidebar's
/// rows; Return or Space opens it (N7, 2026-11-06: Tab is the
/// highlight's too, and nothing else reached it).
struct SupportLine: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 2) {
            question.font(.appCaption).foregroundStyle(.appSecondary)
            Link(destination: ProjectInfo.supportPage) {
                Label { link } icon: { Image(systemName: "cup.and.saucer") }
            }
            .font(.appCallout)
            .modifier(HighlightableControl(cornerRadius: 6, outset: 4, press: { openURL(ProjectInfo.supportPage) }))
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
