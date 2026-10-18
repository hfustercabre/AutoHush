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

/// A title inside a menu part ("Modes", "Timing", "Supported Apps"): a
/// description's size, grey; the part's groups have no lines between them
/// (the user, 2026-10-18).
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
