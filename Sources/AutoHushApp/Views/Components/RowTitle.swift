import SwiftUI

/// A row's title, with an optional description under it.
struct RowTitle: View {
    let title: Text
    var subtitle: Text?
    /// On a selected row's solid accent: all of it white.
    var isOnSelection = false

    init(_ title: Text, subtitle: Text? = nil, isOnSelection: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.isOnSelection = isOnSelection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            title
            if let subtitle {
                subtitle
                    .font(.appCaption)
                    .foregroundStyle(isOnSelection ? AnyShapeStyle(.white) : AnyShapeStyle(.appSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(isOnSelection ? AnyShapeStyle(.white) : AnyShapeStyle(.foreground))
    }
}
