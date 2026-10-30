import SwiftUI

/// A section's title, outside the group it names: in the windows, as System
/// Settings' (the user, 2026-10-17, H3), bold and primary at body size; in
/// the menu ("Turn off for", "Playing Now"), as macOS's own menus' section
/// headers.
struct SectionLabel: View {
    let title: Text
    @Environment(\.isInMenu) private var isInMenu

    init(_ title: Text) { self.title = title }

    var body: some View {
        if isInMenu {
            // As macOS's own menus' section headers ("Output", "Energy Mode"):
            // a step under the rows, semibold, grey (the user, 2026-10-18).
            title.font(.appMenuHeading).foregroundStyle(.appSecondary)
        } else {
            title.font(.appHeadline).foregroundStyle(.primary)
        }
    }
}

extension EnvironmentValues {
    /// Inside the menu's panel, whose headings are a menu's section headers.
    @Entry var isInMenu = false
}

/// The title over a card in Settings and the other windows, e.g. "Timing",
/// outside it as System Settings' are: a section label in line with the
/// card's text, with room above it unless it's the first thing on its tab.
struct SectionHeading: View {
    let title: Text
    var isFirst = false

    init(_ title: Text, isFirst: Bool = false) {
        self.title = title
        self.isFirst = isFirst
    }

    @Environment(\.cardsAreFormSections) private var isFormHeader

    var body: some View {
        SectionLabel(title)
            // In a form's header it lines up with the other sections' titles.
            .padding(.leading, isFormHeader ? 0 : 4)
            .padding(.top, isFirst ? 0 : 6)
            .accessibilityAddTraits(.isHeader)
    }
}
