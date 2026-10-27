import SwiftUI

/// A part's title in the menu and its side windows ("Ignored Apps",
/// "Media Player"), as the settings' page names over their parts.
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
