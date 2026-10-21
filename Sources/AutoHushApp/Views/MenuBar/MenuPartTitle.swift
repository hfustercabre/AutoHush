import SwiftUI

/// A part's title in the menu ("Media Player", "Detection"), as the
/// settings' page names over their parts.
struct MenuPartTitle: View {
    let title: Text

    init(_ title: Text) { self.title = title }

    var body: some View {
        SectionLabel(title)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 14)
            .padding(.top, MenuSpacing.titleTop)
            .padding(.bottom, MenuSpacing.titleBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A section's title inside the menu's settings ("Pausing", "Modes"): a
/// description's size, grey; a line between the sections (the user,
/// 2026-10-21).
struct MenuInnerTitle: View {
    let title: Text

    init(_ title: Text) { self.title = title }

    var body: some View {
        title
            .font(.appCaption)
            .foregroundStyle(.appSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}
